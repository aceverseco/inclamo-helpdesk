# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo new order API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}" }
  let(:customer) { shopify_fixture('customer_orders')['customer'] }
  let(:order_params) { { lines: [{ variant_id: 'gid://shopify/ProductVariant/1', quantity: 1 }], delivery: 'email' } }
  let!(:connection) { create(:inclamo_shopify_connection, account: account, shop_currency: 'UAH') }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    Inclamo::Shopify::CustomerMatcher.remember!(contact, customer['id'])
    stub_shopify(:customer_orders, data: { customer: customer })
    stub_shopify_fixture(:awaiting_payment, 'awaiting_payment')
  end

  def graphql_requests(name)
    a_request(:post, shopify_graphql_url).with { |request| JSON.parse(request.body)['query'].match?(/^(query|mutation) #{name}\b/) }
  end

  describe 'the preview' do
    it 'returns the store calculation to an administrator' do
      stub_shopify_fixture(:new_order_calculate, 'new_order_calculate')

      post "#{base}/actions/new_order_preview", params: { params: order_params }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('total' => { 'amount' => '2062.27', 'currency' => 'UAH' }, 'taxes_included' => true)
      expect(Inclamo::OrderAction.count).to eq(0)
    end

    it 'is forbidden to an agent without the role' do
      post "#{base}/actions/new_order_preview", params: { params: order_params }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('not_allowed')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'gives the store reason when it refuses' do
      stub_shopify_fixture(:new_order_calculate, 'new_order_calculate_refused')

      post "#{base}/actions/new_order_preview", params: { params: order_params }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'store_refused', 'message' => 'Quantity must be greater than or equal to 1')
    end
  end

  it 'starts a new order from an order of the customer' do
    source = shopify_fixture('new_order_from_order')['order']
    stub_shopify(:new_order_from_order, data: { order: source.merge('customer' => { 'id' => customer['id'] }) })

    get "#{base}/actions/new_order_prefill", params: { order_id: source['id'] }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['lines'].pluck('quantity')).to eq([1, 2])
    expect(response.parsed_body['skipped']).to eq([{ 'title' => 'The Archived Snowboard', 'quantity' => 1 }])
  end

  it 'creates the order with the note given beside the recorded parameters' do
    stub_shopify_fixture(:new_order_create, 'new_order_create')
    stub_shopify_fixture(:new_order_invoice_send, 'new_order_invoice_send')

    post "#{base}/actions", params: { action_name: 'new_order', action_id: 'action-new-order-0101', params: order_params, note: 'Gift wrap' },
                            headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('action' => 'new_order', 'outcome' => 'accepted', 'order_id' => nil)
    expect(response.parsed_body['result']).to include('invoice_sent' => true, 'delivery' => 'email')
    expect(a_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body).dig('variables', 'input', 'note') == 'Gift wrap' }).to have_been_made.once
    expect(Inclamo::OrderAction.last.params.to_json).not_to include('Gift wrap')
  end

  describe 'orders awaiting payment in the panel' do
    let(:nodes) { shopify_fixture('awaiting_payment').dig('draftOrders', 'nodes') }

    it 'lists the customer drafts from the helpdesk with items, total, payment link and admin link' do
      get "#{base}/panel", headers: agent.create_new_auth_token

      awaiting = response.parsed_body['awaiting_payment']
      expect(awaiting.pluck('number', 'status', 'invoice_sent')).to eq([[nodes[0]['name'], 'open', false], [nodes[1]['name'], 'open', false], [nodes[2]['name'], 'invoice_sent', true]])
      expect(awaiting.first).to include('total' => { 'amount' => '785.95', 'currency' => 'UAH' }, 'invoice_url' => nodes[0]['invoiceUrl'],
                                        'admin_url' => "https://admin.shopify.com/store/example-store/draft_orders/#{nodes[0]['legacyResourceId']}",
                                        'items' => [{ 'title' => 'The Compare at Price Snowboard', 'quantity' => 1 }])
      expect(a_request(:post, shopify_graphql_url).with do |r|
        JSON.parse(r.body)['variables'] == { 'query' => "customer_id:#{customer['id'].split('/').last} tag:inclamo-helpdesk (status:open OR status:invoice_sent)", 'first' => 5 }
      end).to have_been_made.once
    end

    it 'leaves out a draft once the customer paid it' do
      stub_shopify_fixture(:awaiting_payment, 'awaiting_payment_after_payment')
      paid = shopify_fixture('new_order_draft_completed')['draftOrder']

      get "#{base}/panel", headers: agent.create_new_auth_token

      expect(response.parsed_body['awaiting_payment'].pluck('number')).not_to include(paid['name'])
      expect(response.parsed_body['awaiting_payment'].size).to eq(2)
    end

    it 'reads the list again after an action, and not before' do
      stub_shopify_fixture(:new_order_create, 'new_order_create')
      stub_shopify_fixture(:new_order_invoice_send, 'new_order_invoice_send')

      2.times { get "#{base}/panel", headers: agent.create_new_auth_token }
      expect(graphql_requests('awaiting_payment')).to have_been_made.once

      post "#{base}/actions", params: { action_name: 'new_order', action_id: 'action-new-order-0102', params: order_params }, headers: admin.create_new_auth_token, as: :json
      get "#{base}/panel", headers: agent.create_new_auth_token
      expect(graphql_requests('awaiting_payment')).to have_been_made.twice
    end

    it 'is empty without the draft orders scope, and the panel still shows when the store does not give the list' do
      connection.update!(scopes: %w[read_customers read_orders write_orders read_products])
      get "#{base}/panel", headers: agent.create_new_auth_token
      expect(response.parsed_body['awaiting_payment']).to eq([])

      connection.update!(scopes: %w[read_customers read_orders write_draft_orders read_products])
      Inclamo::Shopify::OrderReader.forget!(account.id)
      stub_shopify(:awaiting_payment, errors: [{ message: 'Internal error', extensions: { code: 'INTERNAL_SERVER_ERROR' } }])
      get "#{base}/panel", headers: agent.create_new_auth_token
      expect(response.parsed_body).to include('state' => 'matched', 'awaiting_payment' => nil)
    end
  end
end
