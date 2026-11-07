# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderActionRunner, 'tags and notes' do
  let(:with_customers) { %w[read_customers read_draft_orders read_orders read_products write_customers write_draft_orders write_orders] }
  let(:record) { create(:inclamo_shopify_connection, scopes: with_customers) }
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:open_order) { shopify_fixture('order_details_open')['order'] }
  let(:order_id) { open_order['id'] }
  let(:customer) { shopify_fixture('customer_marks')['customer'] }
  let(:customer_id) { customer['id'] }
  let(:secret_note) { 'Call +15005550199 before 6 pm, 2 Example Avenue' }

  before { Inclamo::Shopify::OrderReader.forget!(account.id) }

  def member(user)
    AccountUser.find_by(account: account, user: user)
  end

  def runner(user = admin)
    described_class.new(account: account, account_user: member(user), conversation: conversation)
  end

  def private_notes
    conversation.messages.where(private: true)
  end

  def order_tag(operation, tag, user: admin, id: "action-otag-#{operation}-1")
    stub_shopify(:order_details, data: { order: open_order })
    runner(user).perform(action: 'order_tags', action_id: id, order_id: order_id, params: { 'operation' => operation, 'tag' => tag })
  end

  def customer_tag(operation, tag, user: admin, id: "action-ctag-#{operation}-1")
    stub_shopify(:customer_marks, data: { customer: customer })
    runner(user).perform(action: 'customer_tags', action_id: id, customer_id: customer_id, params: { 'operation' => operation, 'tag' => tag })
  end

  def mutation_bodies
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                            .map { |signature| JSON.parse(signature.body) }
                            .select { |body| body['query'].match?(/^mutation /) }
  end

  describe 'order tags and note' do
    it 'adds one tag through tagsAdd, sending only that tag, and leaves a note by the agent' do
      added = stub_shopify(:tags_add, data: shopify_fixture('tags_add_order'))

      result = order_tag('add', 'address-confirmed')

      expect(result).to have_attributes(outcome: 'accepted', order_number: '#1001', params: { 'operation' => 'add', 'tag' => 'address-confirmed' })
      # The order's other tags, also those added in the store meanwhile, are
      # never sent: the store adds this one to whatever it holds.
      expect(added.with { |r| JSON.parse(r.body)['variables'] == { 'id' => order_id, 'tags' => ['address-confirmed'] } }).to have_been_requested.once
      expect(mutation_bodies.map { |body| body['query'][/mutation (\w+)/, 1] }).to eq(['tags_add'])
      expect(private_notes.sole).to have_attributes(content: 'Added the tag "address-confirmed" to order #1001.', sender: admin)
    end

    it 'removes one tag through tagsRemove' do
      removed = stub_shopify(:tags_remove, data: shopify_fixture('tags_remove_order'))

      result = order_tag('remove', 'priority')

      expect(result.outcome).to eq('accepted')
      expect(removed.with { |r| JSON.parse(r.body)['variables'] == { 'id' => order_id, 'tags' => ['priority'] } }).to have_been_requested.once
      expect(private_notes.sole.content).to eq('Removed the tag "priority" from order #1001.')
    end

    it 'replaces the note and records only that it changed' do
      update = stub_shopify(:order_note_update, data: shopify_fixture('order_note_update'))
      stub_shopify(:order_details, data: { order: open_order })

      result = runner.perform(action: 'order_note', action_id: 'action-onote-0001', order_id: order_id, extra: { note: secret_note })

      expect(result).to have_attributes(outcome: 'accepted', params: {})
      expect(update.with { |r| JSON.parse(r.body).dig('variables', 'input') == { 'id' => order_id, 'note' => secret_note } }).to have_been_requested.once
      expect(private_notes.sole.content).to eq('Changed the note of order #1001.')
    end

    it 'clears the note with an empty text' do
      update = stub_shopify(:order_note_update, data: shopify_fixture('order_note_update'))
      stub_shopify(:order_details, data: { order: open_order })

      result = runner.perform(action: 'order_note', action_id: 'action-onote-0002', order_id: order_id, extra: { note: '' })

      expect(result.outcome).to eq('accepted')
      expect(update.with { |r| JSON.parse(r.body).dig('variables', 'input', 'note') == '' }).to have_been_requested.once
    end

    it 'refuses an agent without the role, without calling the store' do
      result = order_tag('add', 'gift', user: agent)

      expect(result).to have_attributes(outcome: 'refused', refusal: 'not_allowed')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
      expect(private_notes).to be_empty
    end

    it 'lets an agent holding the role change tags' do
      Inclamo::OrderRole.create!(account_user: member(agent), granted_by: admin)
      stub_shopify(:tags_add, data: shopify_fixture('tags_add_order'))

      expect(order_tag('add', 'gift', user: agent).outcome).to eq('accepted')
      expect(private_notes.sole.sender).to eq(agent)
    end

    it 'refuses tags and note when the app lacks write_orders, without calling the store' do
      record.update!(scopes: %w[read_customers read_orders write_customers])

      tag = order_tag('add', 'gift')
      note = runner.perform(action: 'order_note', action_id: 'action-onote-0003', order_id: order_id, extra: { note: 'x' })

      expect([tag, note]).to all(have_attributes(outcome: 'refused', refusal: 'missing_scope'))
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'refuses an empty tag and a tag with a comma before asking the store to change anything' do
      expect(order_tag('add', '  ', id: 'action-otag-empty').refusal).to eq('tag_missing')
      expect(order_tag('add', 'a,b', id: 'action-otag-comma').refusal).to eq('tag_has_comma')
      expect(mutation_bodies).to be_empty
      expect(private_notes).to be_empty
    end

    it "shows the store's reason when it refuses a tag, and writes no note" do
      stub_shopify(:tags_add, data: shopify_fixture('tags_add_refused'))

      result = order_tag('add', 'x' * 300)

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'Order tags is invalid')
      expect(private_notes).to be_empty
    end

    it 'changes tags of a cancelled order too' do
      stub_shopify(:tags_add, data: shopify_fixture('tags_add_order'))
      open_order['cancelledAt'] = '2026-11-05T12:00:00Z'

      expect(order_tag('add', 'refund-check').outcome).to eq('accepted')
    end
  end

  describe 'customer tags and note' do
    it 'adds a tag to the customer with write_customers, keeping the customer and no order on record' do
      added = stub_shopify(:tags_add, data: shopify_fixture('tags_add_customer'))

      result = customer_tag('add', 'vip')

      expect(result).to have_attributes(outcome: 'accepted', customer_id: customer_id, order_id: nil, order_number: nil)
      expect(added.with { |r| JSON.parse(r.body)['variables'] == { 'id' => customer_id, 'tags' => ['vip'] } }).to have_been_requested.once
      expect(private_notes.sole.content).to eq('Added the tag "vip" to the customer.')
    end

    it 'removes a tag of the customer' do
      stub_shopify(:tags_remove, data: shopify_fixture('tags_remove_customer'))

      expect(customer_tag('remove', 'wholesale').outcome).to eq('accepted')
      expect(private_notes.sole.content).to eq('Removed the tag "wholesale" from the customer.')
    end

    it "replaces the customer's note" do
      stub_shopify(:customer_marks, data: { customer: customer })
      update = stub_shopify(:customer_note_update, data: shopify_fixture('customer_note_update'))

      result = runner.perform(action: 'customer_note', action_id: 'action-cnote-0001', customer_id: customer_id, extra: { note: 'Prefers phone calls' })

      expect(result).to have_attributes(outcome: 'accepted', params: {})
      expect(update.with { |r| JSON.parse(r.body).dig('variables', 'input') == { 'id' => customer_id, 'note' => 'Prefers phone calls' } }).to have_been_requested.once
      expect(private_notes.sole.content).to eq("Changed the customer's note.")
    end

    it 'refuses when the app lacks write_customers, without calling the store' do
      record.update!(scopes: %w[read_customers read_orders write_orders])

      tag = customer_tag('add', 'vip')
      note = runner.perform(action: 'customer_note', action_id: 'action-cnote-0002', customer_id: customer_id, extra: { note: 'x' })

      expect([tag, note]).to all(have_attributes(outcome: 'refused', refusal: 'missing_scope'))
      expect(record.missing_scopes_for('customer_tags')).to eq(%w[write_customers])
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'refuses in the limited mode, where the store does not share its customers' do
      record.update!(customer_data_mode: 'limited')

      expect(customer_tag('add', 'vip')).to have_attributes(outcome: 'refused', refusal: 'customer_data_hidden')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'refuses an agent without the role' do
      expect(customer_tag('add', 'vip', user: agent)).to have_attributes(outcome: 'refused', refusal: 'not_allowed')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'refuses a customer the store does not have' do
      stub_shopify(:customer_marks, data: { customer: nil })

      result = runner.perform(action: 'customer_tags', action_id: 'action-ctag-gone', customer_id: 'gid://shopify/Customer/1', params: { 'operation' => 'add', 'tag' => 'vip' })

      expect(result).to have_attributes(outcome: 'refused', refusal: 'unknown_customer')
      expect(mutation_bodies).to be_empty
    end

    it 'reads the customer from the store every time, not from the cache' do
      marks = stub_shopify(:customer_marks, data: { customer: customer })
      stub_shopify(:tags_add, data: shopify_fixture('tags_add_customer'))

      customer_tag('add', 'vip', id: 'action-ctag-a')
      customer_tag('add', 'gold', id: 'action-ctag-b')

      expect(marks).to have_been_requested.twice
    end
  end

  describe 'the record of a note' do
    it "never holds the text of a note, in the record or in the private note" do
      stub_shopify(:order_details, data: { order: open_order })
      stub_shopify(:customer_marks, data: { customer: customer })
      stub_shopify(:order_note_update, data: shopify_fixture('order_note_update'))
      stub_shopify(:customer_note_update, data: shopify_fixture('customer_note_update'))

      runner.perform(action: 'order_note', action_id: 'action-onote-text', order_id: order_id, params: { 'note' => secret_note }, extra: { note: secret_note })
      runner.perform(action: 'customer_note', action_id: 'action-cnote-text', customer_id: customer_id, params: { 'note' => secret_note }, extra: { note: secret_note })

      kept = Inclamo::OrderAction.all.map(&:attributes).to_json + private_notes.pluck(:content).join
      expect(Inclamo::OrderAction.pluck(:outcome)).to eq(%w[accepted accepted])
      expect(kept).not_to include('15005550199')
      expect(kept).not_to include('Example Avenue')
      expect(kept).not_to include('6 pm')
    end

    it 'does not repeat an open note change without its text' do
      stub_shopify(:order_details, data: { order: open_order })
      stub_request(:post, shopify_graphql_url).with { |r| r.body.include?('mutation order_note_update') }.to_timeout

      first = runner.perform(action: 'order_note', action_id: 'action-onote-lost', order_id: order_id, extra: { note: 'Leave at the door' })
      expect(first.outcome).to eq('unknown')

      runner.settle_open!

      expect(first.reload.outcome).to eq('unknown')
      expect(a_request(:post, shopify_graphql_url).with { |r| r.body.include?('mutation order_note_update') }).to have_been_made.once
    end
  end
end
