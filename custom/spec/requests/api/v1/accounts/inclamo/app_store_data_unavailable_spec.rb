# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/store_key_stubs')

# While the store app gives no key and the last one has ended, the panel and
# the order endpoints say the store's data is unavailable for now
# (store_data_unavailable): no order of an earlier answer is served, nothing
# is called broken, and the next request asks the app again.
RSpec.describe 'Inclamo order panel, through a store app that does not answer', type: :request do
  include_context 'with the store app for keys'

  let(:account) { provisioned_account }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}" }
  let!(:record) { app_key_connection(account) }
  let(:order) { shopify_fixture('order_details_open')['order'] }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify_fixture(:awaiting_payment, 'awaiting_payment_none')
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify_fixture(:customer_orders, 'customer_orders')
    stub_shopify_fixture(:order_details, 'order_details_open')
    stub_shopify_fixture(:orders_by_number, 'orders_by_number_others')
  end

  def read(path)
    get "#{base}/#{path}", headers: agent.create_new_auth_token
    response
  end

  def the_key_ends_and_the_app_is_down
    record.update!(token_expires_at: 30.seconds.ago)
    stub_request(:post, store_key_url).to_timeout
  end

  it 'serves orders while the key works, though the app does not answer' do
    record.update!(token_expires_at: 3.minutes.from_now)
    stub_request(:post, store_key_url).to_timeout

    expect(read('panel').parsed_body).to include('state' => 'matched')
    expect(response.parsed_body['orders']).not_to be_empty
  end

  it 'says the store data is unavailable once the key has ended, shows no order of an earlier answer, and stays working' do
    expect(read('panel').parsed_body['state']).to eq('matched')
    the_key_ends_and_the_app_is_down

    body = read('panel').parsed_body

    expect(body).to include('state' => 'unavailable', 'reason' => 'store_data_unavailable')
    expect(body).not_to include('orders', 'customer')
    expect(body['connection']).to include('status' => 'working', 'auth_kind' => 'app_key')
    expect(record.reload).to be_working
  end

  it 'answers the order endpoints with the same reason, serving nothing cached' do
    admin = create(:user, account: account, role: :administrator)
    create(:inbox_member, inbox: inbox, user: admin)
    read('panel')
    read("lookup?number=#{CGI.escape('#1001')}")
    the_key_ends_and_the_app_is_down
    headers = admin.create_new_auth_token

    get "#{base}/lookup", params: { number: '#1001' }, headers: headers
    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body).to eq('error' => 'store_unreachable', 'reason' => 'store_data_unavailable')

    put "#{base}/order", params: { order_id: order['id'] }, headers: headers, as: :json
    expect(response.parsed_body).to include('reason' => 'store_data_unavailable')

    post "#{base}/actions/refund_preview", params: { order_id: order['id'], params: { mode: 'full' } }, headers: headers, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body).to include('error' => 'store_unreachable', 'reason' => 'store_data_unavailable')
  end

  it 'records an order action asked for meanwhile as refused for that reason, without calling the store' do
    the_key_ends_and_the_app_is_down
    admin = create(:user, account: account, role: :administrator)
    create(:inbox_member, inbox: inbox, user: admin)
    graphql = stub_request(:post, shopify_graphql_url)

    post "#{base}/actions", params: { action_name: 'cancel', action_id: 'cancel-during-outage', order_id: order['id'], params: { reason: 'customer' } },
                            headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('outcome' => 'refused', 'refusal' => 'store_unreachable', 'store_message' => 'store_data_unavailable')
    expect(graphql).not_to have_been_requested
  end

  it 'shows the orders again on the next read once the app answers, without anyone checking again' do
    the_key_ends_and_the_app_is_down
    expect(read('panel').parsed_body['reason']).to eq('store_data_unavailable')

    clear_app_key_pauses
    stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY))

    expect(read('panel').parsed_body).to include('state' => 'matched')
    expect(record.reload.access_token).to eq(StoreKeyStubs::NEW_KEY)
  end

  describe 'the panel of a connection through the app that is broken' do
    it 'names the reason, and shows no orders' do
      record.update!(status: 'broken', broken_reason: 'app_removed')

      body = read('panel').parsed_body

      expect(body).to include('state' => 'broken')
      expect(body['connection']).to include('broken_reason' => 'app_removed', 'managed_by_app' => true)
      expect(body).not_to include('orders')
    end

    it 'turns broken when the app says the store no longer has it' do
      record.update!(token_expires_at: 30.seconds.ago)
      stub_store_key(key_refusal(404, 'store_not_installed'))

      body = read('panel').parsed_body

      expect(body).to include('state' => 'broken')
      expect(body['connection']).to include('broken_reason' => 'app_removed')
    end
  end
end

# A conversation that arrives while the app gives no key goes to its automation
# rules as one whose store is silent: without store facts, and not held back.
RSpec.describe Inclamo::StoreFactsBeforeRules do
  include_context 'with the store app for keys'

  let(:account) { provisioned_account }
  let!(:record) { app_key_connection(account, expires_at: 30.seconds.ago) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:always) { [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }] }
  let(:spent) { [{ 'attribute_key' => 'shopify_customer_spent', 'filter_operator' => 'is_greater_than', 'values' => ['0'], 'query_operator' => nil, 'custom_attribute_type' => 'conversation_attribute' }] }

  before do
    Inclamo::Shopify::CustomerFacts.ensure_definitions!(account)
    Inclamo::Shopify::ConversationOrder.ensure_definitions!(account)
    create(:automation_rule, account: account, event_name: 'conversation_created', conditions: always, actions: [{ 'action_name' => 'add_label', 'action_params' => ['new'] }])
    create(:automation_rule, account: account, event_name: 'conversation_created', conditions: spent, actions: [{ 'action_name' => 'change_priority', 'action_params' => ['high'] }])
  end

  it 'runs the rules without store facts, and calls the store nothing' do
    stub_request(:post, store_key_url).to_timeout
    graphql = stub_request(:post, shopify_graphql_url)

    AutomationRuleListener.instance.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conversation))

    expect(conversation.reload).to have_attributes(priority: nil, label_list: ['new'], custom_attributes: {})
    expect(graphql).not_to have_been_requested
    expect(record.reload).to be_working
  end
end
