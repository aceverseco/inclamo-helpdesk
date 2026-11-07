# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo conversation order panel API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}" }
  let(:maya_id) { shopify_fixture('customers_search_one').dig('customers', 'nodes', 0, 'id') }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
  end

  def panel(params = {})
    get "#{base}/panel", params: params, headers: agent.create_new_auth_token
    response.parsed_body
  end

  def connect!(*traits, **attributes)
    create(:inclamo_shopify_connection, *traits, account: account, **attributes)
  end

  it 'says the store is not connected' do
    expect(panel).to include('state' => 'not_connected', 'viewer' => { 'administrator' => false, 'can_act_on_orders' => false })
  end

  it 'shows the matched customer with their orders, newest first' do
    connect!
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify_fixture(:customer_orders, 'customer_orders')

    body = panel

    expect(body['state']).to eq('matched')
    expect(body['customer']).to include('name' => 'Maya Example', 'orders_count' => 3)
    expect(body['customer']['total_spent']).to include('amount', 'currency')
    expect(body['orders'].pluck('number')).to eq(%w[#1003 #1002 #1001])
    expect(body['orders'].pluck('created_at')).to eq(body['orders'].pluck('created_at').sort.reverse)
    expect(body['page']).to include('has_more' => false)
  end

  it "shows the customer's tags and note, and the tags and note of each order" do
    connect!
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify_fixture(:customer_orders, 'customer_orders_marks')

    body = panel

    expect(body['customer']).to include('note' => 'Pays by invoice')
    expect(body['customer']['tags']).to include('wholesale')
    expect(body['orders'].first).to include('note' => 'Leave at the door')
    expect(body['orders'].first['tags']).to include('gift', 'priority')
  end

  it 'loads the next page of orders' do
    connect!
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    first = shopify_fixture('customer_orders_page_1')
    cursor = first.dig('customer', 'orders', 'pageInfo', 'endCursor')
    stub_request(:post, shopify_graphql_url).with { |r| (b = JSON.parse(r.body))['query'].include?('query customer_orders') && b.dig('variables', 'after').nil? }
                                            .to_return(status: 200, body: { data: first }.to_json, headers: ShopifyStubs::JSON_HEADERS)
    stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body).dig('variables', 'after') == cursor }
                                            .to_return(status: 200, body: { data: shopify_fixture('customer_orders_page_2') }.to_json, headers: ShopifyStubs::JSON_HEADERS)

    expect(panel['page']).to eq('has_more' => true, 'cursor' => cursor)
    expect(panel(after: cursor)['orders'].pluck('number')).to eq(%w[#1001])
  end

  it 'lists the candidates instead of orders when the match is not unique, and remembers the agent\'s choice' do
    connect!
    maya = shopify_fixture('customers_search_one').dig('customers', 'nodes', 0)
    stub_shopify(:customers_search, data: { customers: { nodes: [maya, maya.merge('id' => 'gid://shopify/Customer/2', 'displayName' => 'Mia Example')] } })
    stub_shopify_fixture(:customer_orders, 'customer_orders')

    body = panel
    expect(body['state']).to eq('ambiguous')
    expect(body).not_to include('orders')
    expect(body['candidates'].size).to eq(2)

    post "#{base}/customer", params: { customer_id: maya_id }, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['state']).to eq('matched')
    another = create(:conversation, account: account, inbox: inbox, contact: contact)
    get "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{another.display_id}/panel", headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('state' => 'matched')
  end

  it 'offers lookup by order number when nobody matches, and can keep that customer' do
    connect!
    stub_shopify_fixture(:customers_search, 'customers_search_none')
    stub_shopify_fixture(:orders_by_number, 'orders_by_number_others')
    stub_shopify(:customer_orders, data: { customer: { id: 'gid://shopify/Customer/9', displayName: 'Noah Example', numberOfOrders: '1', orders: { nodes: [], pageInfo: { hasNextPage: false, endCursor: nil } } } })

    expect(panel['state']).to eq('none')

    get "#{base}/lookup", params: { number: '#1004' }, headers: agent.create_new_auth_token
    found = response.parsed_body
    expect(found).to include('found' => true)
    expect(found['order']).to include('number' => '#1004')
    expect(found['order']['customer']['name']).to eq('Noah Example')

    post "#{base}/customer", params: { customer_id: found['order']['customer']['id'] }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['state']).to eq('matched')
  end

  it 'says so when the order number does not exist' do
    connect!
    stub_shopify_fixture(:orders_by_number, 'orders_by_number_none')

    get "#{base}/lookup", params: { number: '999999' }, headers: agent.create_new_auth_token

    expect(response.parsed_body).to eq('found' => false)
  end

  it 'offers only the lookup for a contact without email and phone' do
    connect!
    contact.update!(email: nil, phone_number: nil)

    expect(panel['state']).to eq('no_identifier')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'works by order number only when the store hides customer data' do
    connect!(customer_data_mode: 'limited')
    stub_shopify_fixture(:orders_by_number_limited, 'orders_by_number_limited_open')

    expect(panel['state']).to eq('limited')
    expect(panel['connection']['actions'].find { |action| action['name'] == 'address' }).to include('available' => false, 'reason' => 'customer_data_hidden')

    get "#{base}/lookup", params: { number: '1001' }, headers: agent.create_new_auth_token
    order = response.parsed_body['order']
    expect(order).to include('number' => '#1001', 'customer' => nil, 'shipping_address' => nil)
    expect(order['items'].size).to eq(3)
    expect(order['shipments']).to eq([])
  end

  it 'shows a broken connection instead of orders, also when it breaks during the read' do
    record = connect!(:legacy)
    stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{}')

    expect(panel).to include('state' => 'broken')
    expect(record.reload).to be_broken
    expect(panel).to include('state' => 'broken')
    expect(panel).not_to include('orders')
    expect(WebMock).to have_requested(:post, shopify_graphql_url).once
  end

  it 'says the store did not answer, and offers no stale orders' do
    connect!
    stub_request(:post, shopify_graphql_url).to_timeout

    expect(panel).to include('state' => 'unavailable', 'reason' => 'timeout')
    expect(panel).not_to include('orders')
  end

  it 'says the store refuses the app when a store that was empty on connecting gets its first customers' do
    record = connect!
    stub_shopify(:customers_search, errors: access_denied('customers'))

    expect(panel).to include('state' => 'refused')
    expect(panel).not_to include('orders')
    expect(record.reload).to be_working
  end

  it 'writes nothing to the database while reading' do
    connect!
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify_fixture(:customer_orders, 'customer_orders')
    headers = agent.create_new_auth_token
    conversation
    writes = []
    watch = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      writes << sql if sql.match?(/\A\s*(INSERT|UPDATE|DELETE)/i) && !sql.match?(/"(users|access_tokens)"/)
    end

    ActiveSupport::Notifications.subscribed(watch, 'sql.active_record') do
      get "#{base}/panel", headers: headers
    end

    expect(response.parsed_body['state']).to eq('matched')
    expect(writes).to eq([])
  end

  describe 'the order the conversation is about' do
    let(:shipped_id) { shopify_fixture('order_details_shipped').dig('order', 'id') }

    before do
      connect!
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      stub_shopify_fixture(:customer_orders, 'customer_orders')
      stub_shopify_fixture(:order_details, 'order_details_shipped')
    end

    it 'is marked by the agent, shown by the panel and written to the conversation' do
      put "#{base}/order", params: { order_id: shipped_id }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['marked_order']).to include('number' => '#1002')
      expect(conversation.reload.custom_attributes).to include('shopify_order_number' => '#1002', 'shopify_order_tracking_number' => 'E2Et001A')
      expect(panel['marked_order']).to include('number' => '#1002')
    end

    it 'is refreshed when the panel reads an order that changed in the store' do
      put "#{base}/order", params: { order_id: shipped_id }, headers: agent.create_new_auth_token, as: :json
      conversation.reload.update!(custom_attributes: conversation.custom_attributes.merge('shopify_order_fulfillment_status' => 'unfulfilled'))

      panel

      expect(conversation.reload.custom_attributes['shopify_order_fulfillment_status']).to eq('fulfilled')
    end

    it 'is cleared by the agent' do
      put "#{base}/order", params: { order_id: shipped_id }, headers: agent.create_new_auth_token, as: :json
      delete "#{base}/order", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['marked_order']).to be_nil
      expect(conversation.reload.custom_attributes).not_to include('shopify_order_number')
    end

    it 'refuses something that is not an order of the store' do
      put "#{base}/order", params: { order_id: 'gid://shopify/Customer/1' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.custom_attributes).not_to include('shopify_order_number')
    end
  end

  it 'makes the order attributes known to Chatwoot when a store is connected' do
    admin = create(:user, account: account, role: :administrator)
    stub_token_exchange
    stub_shopify(:shop_info, data: shop_info_data)
    stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

    post "/api/v1/accounts/#{account.id}/inclamo/shopify/connection",
         params: { shop_domain: 'example-store.myshopify.com', client_id: 'id', client_secret: 'secret' }, headers: admin.create_new_auth_token, as: :json
    get "/api/v1/accounts/#{account.id}/custom_attribute_definitions", params: { attribute_model: 'conversation_attribute' }, headers: admin.create_new_auth_token

    expect(response.parsed_body.pluck('attribute_key')).to include('shopify_order_number', 'shopify_order_tracking_link')
  end

  it 'is closed to an agent who cannot see the conversation' do
    connect!
    outsider = create(:user, account: account, role: :agent)

    get "#{base}/panel", headers: outsider.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end
end
