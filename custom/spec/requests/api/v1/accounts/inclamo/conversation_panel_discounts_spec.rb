# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo conversation order panel, discount codes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: admin)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify_fixture(:awaiting_payment, 'awaiting_payment_none')
    stub_shopify_fixture(:customers_search, 'customers_search_none')
    Inclamo::DiscountPreset.create!(account: account, name: 'Sorry', kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer')
  end

  def panel(as)
    get "#{base}/panel", headers: as.create_new_auth_token
    response.parsed_body
  end

  def discount_report(body)
    body.dig('connection', 'actions').find { |action| action['name'] == 'discount' }
  end

  it 'gives an administrator the right and the presets, and names write_discounts when the app lacks it' do
    create(:inclamo_shopify_connection, account: account)

    body = panel(admin)

    expect(body['viewer']).to include('can_give_discounts' => true)
    expect(body.dig('viewer', 'discount_presets')).to eq([{ 'id' => Inclamo::DiscountPreset.last.id, 'name' => 'Sorry', 'kind' => 'percentage', 'value' => '10',
                                                            'expires_in_days' => 30, 'usage_limit' => 1, 'audience' => 'customer' }])
    expect(discount_report(body)).to include('available' => false, 'reason' => 'missing_scope', 'missing_scopes' => ['write_discounts'])
  end

  it 'reports the discount as available on a connection with write_discounts' do
    create(:inclamo_shopify_connection, account: account, scopes: %w[read_customers read_orders write_discounts])

    expect(discount_report(panel(admin))).to include('available' => true, 'missing_scopes' => [])
  end

  it 'gives no right and no presets to an agent without the right, even with the order-actions role' do
    create(:inclamo_shopify_connection, account: account, scopes: %w[read_customers read_orders write_discounts])
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent))

    body = panel(agent)

    expect(body['viewer']).to include('can_act_on_orders' => true, 'can_give_discounts' => false, 'discount_presets' => [])
  end

  it 'says to any agent whether the catalogue can be searched for "Insert product"' do
    connection = create(:inclamo_shopify_connection, account: account)
    expect(panel(agent).dig('connection', 'products_readable')).to be(true)

    connection.update!(scopes: %w[read_customers read_orders])
    expect(panel(agent).dig('connection', 'products_readable')).to be(false)
  end

  it 'gives the presets to an agent with the right, also when the contact matches no customer' do
    create(:inclamo_shopify_connection, account: account, scopes: %w[read_customers read_orders write_discounts])
    Inclamo::DiscountGrant.create!(account_user: AccountUser.find_by(account: account, user: agent))

    body = panel(agent)

    expect(body['state']).to eq('none')
    expect(body['viewer']).to include('can_act_on_orders' => false, 'can_give_discounts' => true)
    expect(body.dig('viewer', 'discount_presets').pluck('name')).to eq(['Sorry'])
  end
end
