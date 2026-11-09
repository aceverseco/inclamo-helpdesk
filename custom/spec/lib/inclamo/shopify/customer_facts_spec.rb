# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::CustomerFacts do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact, custom_attributes: { 'priority_note' => 'vip' }) }
  let(:facts) { described_class.new(conversation) }
  let(:maya) { shopify_fixture('customers_search_one').dig('customers', 'nodes', 0) }

  before { Inclamo::Shopify::OrderReader.forget!(account.id) }

  def attributes
    conversation.reload.custom_attributes
  end

  describe 'a contact who is one customer of the store' do
    before { stub_shopify_fixture(:customers_search, 'customers_search_one') }

    it 'writes the order count, the amount spent, the tags and the latest order' do
      facts.refresh!

      expect(attributes).to include(
        'shopify_is_customer' => 'yes', 'shopify_customer_orders' => 3, 'shopify_customer_spent' => 5357.65,
        'shopify_customer_tags' => 'e2e, e2e-t001', 'shopify_last_order_payment_status' => 'partially_refunded',
        'shopify_last_order_fulfillment_status' => 'unfulfilled', 'shopify_last_order_total' => 1399.9,
        'shopify_last_order_tags' => 'e2e, e2e-t001'
      )
    end

    it 'writes no personal data and keeps the other attributes of the conversation' do
      facts.refresh!

      expect(attributes.to_json).not_to match(/Maya|example\.com|\+1500|Customer/)
      expect(attributes['priority_note']).to eq('vip')
      expect(attributes.keys - ['priority_note']).to match_array(described_class::KEYS)
    end

    it 'asks the store once' do
      facts.refresh!

      expect(WebMock).to have_requested(:post, shopify_graphql_url).once
    end

    it 'writes nothing when nothing changed' do
      facts.refresh!

      expect { described_class.new(conversation.reload).refresh! }.not_to(change { conversation.reload.updated_at })
    end

    it 'replaces what was written before' do
      facts.refresh!
      Inclamo::Shopify::OrderReader.forget!(account.id)
      richer = maya.merge('numberOfOrders' => '4', 'amountSpent' => { 'amount' => '6000.0', 'currencyCode' => 'UAH' }, 'tags' => ['wholesale'])
      stub_shopify(:customers_search, data: { customers: { nodes: [richer] } })

      described_class.new(conversation.reload).refresh!

      expect(attributes).to include('shopify_customer_orders' => 4, 'shopify_customer_spent' => 6000, 'shopify_customer_tags' => 'wholesale')
    end
  end

  describe 'a customer without orders the store shows' do
    it 'has no facts about a latest order, and empty tags rather than none' do
      newcomer = maya.merge('numberOfOrders' => '0', 'amountSpent' => { 'amount' => '0.0', 'currencyCode' => 'UAH' },
                            'tags' => [], 'latestOrders' => { 'nodes' => [] })
      stub_shopify(:customers_search, data: { customers: { nodes: [newcomer] } })

      facts.refresh!

      expect(attributes).to include('shopify_is_customer' => 'yes', 'shopify_customer_orders' => 0, 'shopify_customer_spent' => 0,
                                    'shopify_customer_tags' => '')
      expect(attributes.keys.grep(/last_order/)).to be_empty
    end
  end

  describe 'a customer with more tags than a text attribute holds' do
    it 'keeps as many whole tags as fit' do
      many = Array.new(250) { |index| format('segment-%03d', index) }

      text = described_class.of(maya.merge('tags' => many))['shopify_customer_tags']

      expect(text.length).to be <= 1500
      expect(text).to start_with('segment-000, segment-001').and end_with(format('segment-%03d', text.split(', ').size - 1))
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('shopify_customer_tags' => text))
    end
  end

  describe 'a customer an agent chose earlier' do
    before { Inclamo::Shopify::CustomerMatcher.remember!(contact, maya['id']) }

    it 'is read by id, without a search' do
      stub_shopify_fixture(:customer_orders, 'customer_orders')

      facts.refresh!

      expect(attributes).to include('shopify_is_customer' => 'yes', 'shopify_customer_orders' => 3, 'shopify_last_order_total' => 1399.9)
      expect(WebMock).to have_requested(:post, shopify_graphql_url).once
    end

    it 'is not a customer once the store no longer has them' do
      stub_shopify(:customer_orders, data: { customer: nil })

      facts.refresh!

      expect(attributes.slice(*described_class::KEYS)).to eq('shopify_is_customer' => 'no')
    end
  end

  describe 'a contact who is not a customer' do
    it 'is marked as not a customer, with no other fact' do
      stub_shopify_fixture(:customers_search, 'customers_search_none')

      facts.refresh!

      expect(attributes).to eq('priority_note' => 'vip', 'shopify_is_customer' => 'no')
    end

    it 'loses the facts written while they still matched a customer' do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      facts.refresh!
      Inclamo::Shopify::OrderReader.forget!(account.id)
      WebMock.reset!
      stub_shopify_fixture(:customers_search, 'customers_search_none')

      described_class.new(conversation.reload).refresh!

      expect(attributes).to eq('priority_note' => 'vip', 'shopify_is_customer' => 'no')
    end

    it 'is marked without asking the store when the contact has no email and no phone' do
      contact.update!(email: nil, phone_number: nil)

      facts.refresh!

      expect(attributes['shopify_is_customer']).to eq('no')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'a contact who matches several customers' do
    it 'gets no facts at all: nothing is guessed' do
      twin = maya.merge('id' => 'gid://shopify/Customer/2', 'displayName' => 'Mia Example')
      stub_shopify(:customers_search, data: { customers: { nodes: [maya, twin] } })

      facts.refresh!

      expect(attributes).to eq('priority_note' => 'vip')
    end
  end

  describe 'a store connected in the limited mode' do
    before { record.update!(customer_data_mode: 'limited') }

    it 'writes no customer facts and asks the store nothing' do
      facts.refresh!

      expect(attributes).to eq('priority_note' => 'vip')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'removes the facts written before the store hid its customers' do
      facts.write!(described_class.of(maya))

      described_class.new(conversation.reload).refresh!

      expect(attributes).to eq('priority_note' => 'vip')
    end
  end

  describe 'an account without a working store' do
    it 'writes nothing when the connection is broken' do
      record.update!(status: 'broken')

      expect(facts.refresh!).to be_nil
      expect(attributes).to eq('priority_note' => 'vip')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'writes nothing when no store is connected' do
      record.destroy!

      expect(described_class.new(conversation).refresh!).to be_nil
      expect(attributes).to eq('priority_note' => 'vip')
    end
  end

  describe 'a store that does not answer' do
    it 'raises and leaves the conversation as it was' do
      stub_request(:post, shopify_graphql_url).to_timeout

      expect { facts.refresh! }.to raise_error(Inclamo::Shopify::Error)
      expect(attributes).to eq('priority_note' => 'vip')
    end
  end

  describe 'attribute definitions' do
    let(:definitions) { CustomAttributeDefinition.where(account: account, attribute_model: :conversation_attribute) }

    it 'are the eight facts, created once per account' do
      2.times { described_class.ensure_definitions!(account) }

      expect(definitions.pluck(:attribute_key)).to match_array(described_class::KEYS)
      expect(described_class::KEYS.size).to eq(8)
      numbers = %w[shopify_customer_orders shopify_customer_spent shopify_last_order_total]
      expect(definitions.where(attribute_display_type: :number).pluck(:attribute_key)).to match_array(numbers)
      expect(definitions.find_by(attribute_key: 'shopify_is_customer')).to have_attributes(attribute_display_type: 'list', attribute_values: %w[yes no])
    end

    it 'are created by the first write in an account connected before they existed' do
      stub_shopify_fixture(:customers_search, 'customers_search_one')

      facts.refresh!

      expect(definitions.pluck(:attribute_key)).to match_array(described_class::KEYS)
    end

    it 'come back when one was deleted' do
      described_class.ensure_definitions!(account)
      definitions.find_by(attribute_key: 'shopify_customer_spent').destroy!

      described_class.ensure_definitions!(account)

      expect(definitions.pluck(:attribute_key)).to match_array(described_class::KEYS)
    end
  end

  # Chatwoot's own filter decides whether a rule fires; these go through it.
  describe 'as conditions of an automation rule' do
    def rule_matches?(key, operator, value)
      rule = create(:automation_rule, account: account, event_name: 'conversation_created', actions: [{ 'action_name' => 'add_label', 'action_params' => ['x'] }],
                                      conditions: [{ 'attribute_key' => key, 'filter_operator' => operator, 'values' => [value], 'query_operator' => nil,
                                                     'custom_attribute_type' => 'conversation_attribute' }])
      AutomationRules::ConditionsFilterService.new(rule, conversation.reload).perform
    end

    before do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      facts.refresh!
    end

    it 'compares the numbers with "greater than" and "less than"' do
      expect(rule_matches?('shopify_customer_spent', 'is_greater_than', '500')).to be(true)
      expect(rule_matches?('shopify_customer_spent', 'is_greater_than', '6000')).to be(false)
      expect(rule_matches?('shopify_customer_orders', 'is_less_than', '5')).to be(true)
      expect(rule_matches?('shopify_last_order_total', 'is_less_than', '1000')).to be(false)
    end

    it 'finds a tag with "contains"' do
      expect(rule_matches?('shopify_customer_tags', 'contains', 'e2e-t001')).to be(true)
      expect(rule_matches?('shopify_customer_tags', 'contains', 'wholesale')).to be(false)
      expect(rule_matches?('shopify_last_order_tags', 'contains', 'E2E')).to be(true)
    end

    it 'compares the statuses and "is a customer" by equality' do
      expect(rule_matches?('shopify_last_order_fulfillment_status', 'equal_to', 'unfulfilled')).to be(true)
      expect(rule_matches?('shopify_last_order_payment_status', 'equal_to', 'paid')).to be(false)
      expect(rule_matches?('shopify_is_customer', 'equal_to', 'yes')).to be(true)
      expect(rule_matches?('shopify_is_customer', 'equal_to', 'no')).to be(false)
    end
  end
end

RSpec.describe 'Store facts when a store is connected', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'makes the eight facts known to the automation rule editor' do
    stub_token_exchange
    stub_shopify(:shop_info, data: shop_info_data)
    stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

    post "/api/v1/accounts/#{account.id}/inclamo/shopify/connection",
         params: { shop_domain: 'example-store.myshopify.com', client_id: 'client-id', client_secret: 'client-secret' },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    keys = CustomAttributeDefinition.where(account: account, attribute_model: :conversation_attribute).pluck(:attribute_key)
    expect(keys).to include(*Inclamo::Shopify::CustomerFacts::KEYS)
  end
end

RSpec.describe 'Store facts when the order panel reads the customer', type: :request do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify_fixture(:customer_orders, 'customer_orders')
  end

  def read_panel
    stub_shopify_fixture(:awaiting_payment, 'awaiting_payment_none')
    get "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}/panel", headers: agent.create_new_auth_token
    expect(response.parsed_body['state']).to eq('matched')
  end

  it 'writes them' do
    read_panel

    expect(conversation.reload.custom_attributes).to include(
      'shopify_is_customer' => 'yes', 'shopify_customer_orders' => 3, 'shopify_customer_spent' => 5357.65,
      'shopify_last_order_payment_status' => 'partially_refunded', 'shopify_last_order_total' => 1399.9
    )
  end

  it 'writes nothing when nothing changed' do
    read_panel

    expect { read_panel }.not_to(change { conversation.reload.updated_at })
  end

  it 'replaces them when the store says something new' do
    read_panel
    Inclamo::Shopify::OrderReader.forget!(account.id)
    richer = shopify_fixture('customer_orders')
    richer['customer'].merge!('numberOfOrders' => '4', 'amountSpent' => { 'amount' => '6943.55', 'currencyCode' => 'UAH' })
    richer['customer']['latestOrders']['nodes'][0].merge!('displayFinancialStatus' => 'PAID', 'displayFulfillmentStatus' => 'FULFILLED')
    WebMock.reset!
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify(:customer_orders, data: richer)

    read_panel

    expect(conversation.reload.custom_attributes).to include(
      'shopify_customer_orders' => 4, 'shopify_customer_spent' => 6943.55,
      'shopify_last_order_payment_status' => 'paid', 'shopify_last_order_fulfillment_status' => 'fulfilled'
    )
  end

  it 'keeps the order the conversation is about next to them' do
    Inclamo::Shopify::ConversationOrder.new(conversation).mark!(shopify_fixture('order_details_shipped')['order'])
    stub_shopify_fixture(:order_details, 'order_details_shipped')

    read_panel

    expect(conversation.reload.custom_attributes).to include('shopify_order_number' => '#1002', 'shopify_customer_orders' => 3)
  end
end
