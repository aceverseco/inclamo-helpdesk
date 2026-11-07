# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderActionRunner, 'discount code' do
  let(:record) do
    create(:inclamo_shopify_connection, shop_currency: 'UAH',
                                        scopes: %w[read_customers read_draft_orders read_orders read_products write_draft_orders write_orders write_discounts read_discounts])
  end
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:customer) { shopify_fixture('customer_orders')['customer'] }
  let(:runner) { runner_for(admin) }
  let(:created) { shopify_fixture('discount_code_create_percentage') }
  let(:code_format) { /\ATHANKS-[A-HJ-NP-Z2-9]{8}\z/ }
  let(:sorry) do
    Inclamo::DiscountPreset.create!(account: account, name: 'Sorry', kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer')
  end
  let(:thanks) do
    Inclamo::DiscountPreset.create!(account: account, name: 'Thanks', kind: 'amount', value: '5.00', expires_in_days: nil, usage_limit: 3, audience: 'anyone')
  end

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    Inclamo::Shopify::CustomerMatcher.remember!(contact, customer['id'])
    stub_shopify(:customer_orders, data: { customer: customer })
    stub_shopify_fixture(:discount_code_create, 'discount_code_create_percentage')
  end

  def runner_for(user)
    described_class.new(account: account, account_user: AccountUser.find_by(account: account, user: user), conversation: conversation)
  end

  def operation_requests(name)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^(query|mutation) #{name}\b/) && (!block_given? || yield(body['variables']))
    end
  end

  def sent_inputs
    inputs = []
    expect(operation_requests('discount_code_create') { |variables| inputs << variables['input'] }).to have_been_made.at_least_once
    inputs.uniq
  end

  def notes
    conversation.messages.where(private: true).pluck(:content)
  end

  def give(preset, id: 'action-discount-0001', as: runner)
    as.perform(action: 'discount', action_id: id, order_id: nil, params: { 'preset_id' => preset.id })
  end

  def taken
    { discountCodeBasicCreate: { codeDiscountNode: nil, userErrors: [{ field: %w[basicCodeDiscount code], code: 'TAKEN', message: 'Code must be unique. Please try a different code.' }] } }
  end

  describe 'a code from a preset' do
    it 'makes a percentage code for the matched customer, usable once, expiring in 30 days' do
      freeze_time do
        result = give(sorry)

        expect(result).to have_attributes(outcome: 'accepted', order_id: nil)
        input = sent_inputs.sole
        expect(input).to include('code' => a_string_matching(code_format), 'title' => "Sorry · helpdesk conversation #{conversation.display_id}",
                                 'endsAt' => 30.days.from_now.utc.iso8601, 'usageLimit' => 1, 'appliesOncePerCustomer' => false,
                                 'context' => { 'customers' => { 'add' => [customer['id']] } },
                                 'customerGets' => { 'value' => { 'percentage' => 0.1 }, 'items' => { 'all' => true } })
        expect(result.as_json[:result]).to eq('code' => input['code'], 'discount_id' => created.dig('discountCodeBasicCreate', 'codeDiscountNode', 'id'))
      end
    end

    it 'makes an amount code for anyone that never expires, usable 3 times, once per buyer' do
      result = give(thanks)

      expect(result.outcome).to eq('accepted')
      expect(sent_inputs.sole).to include('endsAt' => nil, 'usageLimit' => 3, 'appliesOncePerCustomer' => true, 'context' => { 'all' => 'ALL' },
                                          'customerGets' => { 'value' => { 'discountAmount' => { 'amount' => '5', 'appliesOnEachItem' => false } }, 'items' => { 'all' => true } })
    end

    it 'takes the expiry of the preset in days' do
      sorry.update!(expires_in_days: 7)

      freeze_time do
        give(sorry)

        expect(sent_inputs.sole['endsAt']).to eq(7.days.from_now.utc.iso8601)
      end
    end

    it 'gives anyone a code for anyone when the contact matches no customer, and refuses a preset for the customer' do
      conversation.update!(contact: create(:contact, account: account, email: 'nobody.example.t001@example.com'))
      stub_shopify_fixture(:customers_search, 'customers_search_none')

      refused = give(sorry)
      expect(refused).to have_attributes(outcome: 'refused', refusal: 'customer_not_found')
      expect(operation_requests('discount_code_create')).not_to have_been_made

      expect(give(thanks, id: 'action-discount-0002').outcome).to eq('accepted')
      expect(sent_inputs.sole['context']).to eq('all' => 'ALL')
    end

    it 'keeps the conditions it was made with when the preset changes later' do
      result = give(sorry)
      sorry.update!(value: '50', expires_in_days: nil)

      expect(result.reload.params).to include('preset_id' => sorry.id, 'preset_name' => 'Sorry', 'kind' => 'percentage', 'value' => '10', 'usage_limit' => 1,
                                              'audience' => 'customer', 'customer_id' => customer['id'], 'code' => a_string_matching(code_format))
      expect(result.params['expires_at']).to be_present
      expect(result.params.to_json + result.progress.to_json).not_to include('maya', 'Example')
    end

    it 'leaves a private note naming the preset, the code, the value and the expiry' do
      freeze_time do
        result = give(sorry)

        expect(notes).to eq(["Created discount code #{result.params['code']} from the preset \"Sorry\": 10% off the order, usable once, " \
                             "for this customer only, expires on #{30.days.from_now.to_date.iso8601}."])
        expect(conversation.messages.where(private: true).last.sender).to eq(admin)
      end
    end

    it 'names an amount, several uses and no expiry in the note' do
      result = give(thanks)

      expect(notes).to eq(["Created discount code #{result.params['code']} from the preset \"Thanks\": 5.00 UAH off the order, usable 3 times, " \
                           'for anyone, once per buyer, never expires.'])
    end
  end

  describe 'who may give a code' do
    before { create(:inbox_member, inbox: conversation.inbox, user: agent) }

    it 'is refused to an agent with the order-actions role but without the right, with no store call' do
      Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent))

      expect(give(sorry, as: runner_for(agent)).refusal).to eq('not_allowed')
      expect(operation_requests('discount_code_create')).not_to have_been_made
    end

    it 'is given to an agent with the right but without the order-actions role' do
      Inclamo::DiscountGrant.create!(account_user: AccountUser.find_by(account: account, user: agent))

      expect(give(sorry, as: runner_for(agent)).outcome).to eq('accepted')
    end

    it 'is refused without write_discounts and for an unknown preset, with no store call' do
      record.update!(scopes: %w[read_customers read_orders write_orders])
      expect(give(sorry).refusal).to eq('missing_scope')
      expect(record.missing_scopes_for('discount')).to eq(%w[write_discounts])

      record.update!(scopes: %w[read_customers read_orders write_discounts])
      fresh = runner_for(admin)
      expect(fresh.perform(action: 'discount', action_id: 'action-discount-0002', order_id: nil, params: { 'preset_id' => 0 }).refusal).to eq('unknown_preset')
      other = Inclamo::DiscountPreset.create!(account: create(:account), name: 'Theirs', kind: 'percentage', value: '90', usage_limit: 1, audience: 'anyone')
      expect(fresh.perform(action: 'discount', action_id: 'action-discount-0003', order_id: nil, params: { 'preset_id' => other.id }).refusal).to eq('unknown_preset')
      expect(operation_requests('discount_code_create')).not_to have_been_made
    end
  end

  describe 'the store saying no' do
    it 'tries a new text when the text is taken' do
      stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation discount_code_create') }
                                              .to_return({ status: 200, body: { data: taken }.to_json, headers: ShopifyStubs::JSON_HEADERS },
                                                         { status: 200, body: { data: shopify_fixture('discount_code_create_percentage') }.to_json, headers: ShopifyStubs::JSON_HEADERS })

      result = give(sorry)

      expect(result.outcome).to eq('accepted')
      codes = sent_inputs.pluck('code')
      expect(codes.size).to eq(2)
      expect(codes.uniq.size).to eq(2)
      expect(result.as_json[:result]['code']).to eq(codes.last)
      expect(result.params['code']).to eq(codes.last)
    end

    it 'gives up with the store reason after three taken texts, and leaves no note' do
      stub_shopify(:discount_code_create, data: taken)

      result = give(sorry)

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'Code must be unique. Please try a different code.')
      expect(operation_requests('discount_code_create')).to have_been_made.times(3)
      expect(notes).to be_empty
    end

    it 'keeps a refused code in the record with the store reason and leaves no note' do
      stub_shopify(:discount_code_create, data: { discountCodeBasicCreate: { codeDiscountNode: nil, userErrors: [{ field: %w[basicCodeDiscount usageLimit], code: 'INVALID', message: 'Usage limit is invalid' }] } })

      result = give(sorry)

      expect(Inclamo::OrderAction.find_by(action_id: 'action-discount-0001')).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'Usage limit is invalid')
      expect(result.as_json[:result]).to eq({})
      expect(notes).to be_empty
      expect(operation_requests('discount_code_create')).to have_been_made.once
    end
  end

  describe 'an attempt whose answer was lost' do
    let(:lost_create) { stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation discount_code_create') }.to_timeout }

    def lose_first_attempt
      lost_create
      first = give(sorry)
      expect(first.outcome).to eq('unknown')
      remove_request_stub(lost_create)
      first
    end

    # The store's answer for the lost code, under the title this conversation gives it.
    def stub_found
      node = shopify_fixture('discount_code_by_code_found')['codeDiscountNodeByCode']
      title = "Sorry · helpdesk conversation #{conversation.display_id}"
      stub_shopify(:discount_code_by_code, data: { codeDiscountNodeByCode: node.merge('codeDiscount' => node['codeDiscount'].merge('title' => title)) })
    end

    it 'stays unknown for a while, then is finished from the code the store has, without a second code' do
      first = lose_first_attempt

      expect(give(sorry).outcome).to eq('unknown')

      stub_found
      again = travel_to(31.seconds.from_now) { give(sorry) }

      expect(again).to have_attributes(outcome: 'accepted')
      expect(again.as_json[:result]['code']).to eq(first.params['code'])
      expect(operation_requests('discount_code_by_code') { |variables| variables['code'] == first.params['code'] }).to have_been_made.once
      expect(operation_requests('discount_code_create')).to have_been_made.once
      expect(notes.size).to eq(1)
    end

    it 'is refused as not created when the store has no such code' do
      lose_first_attempt
      stub_shopify_fixture(:discount_code_by_code, 'discount_code_by_code_none')

      travel_to(31.seconds.from_now) { runner.settle_open! }

      expect(Inclamo::OrderAction.last).to have_attributes(outcome: 'refused', refusal: 'not_created')
      expect(operation_requests('discount_code_create')).to have_been_made.once
      expect(notes).to be_empty
    end
  end
end
