# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo tags and notes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}" }
  let(:all_scopes) { %w[read_customers read_draft_orders read_orders read_products write_customers write_draft_orders write_orders] }
  let(:customer) { shopify_fixture('customer_marks')['customer'] }
  let(:order) { shopify_fixture('order_marks')['order'] }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
  end

  def connect!(**attributes)
    create(:inclamo_shopify_connection, account: account, scopes: all_scopes, **attributes)
  end

  def panel(user = admin)
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify_fixture(:customer_orders, 'customer_orders_marks')
    get "#{base}/panel", headers: user.create_new_auth_token
    response.parsed_body
  end

  describe 'the connection reports write_customers' do
    it 'lists the scope and makes the customer actions available when the app holds it' do
      stub_token_exchange
      stub_shopify(:shop_info, data: shop_info_data(scopes: all_scopes))
      stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

      post "/api/v1/accounts/#{account.id}/inclamo/shopify/connection",
           params: { shop_domain: 'example-store.myshopify.com', client_id: 'client-id', client_secret: 'client-secret' }, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['scopes']).to include('write_customers')
      expect(body['actions'].find { |action| action['name'] == 'customer_tags' }).to include('available' => true, 'missing_scopes' => [])
    end

    it 'names write_customers as missing for the customer actions only' do
      connect!(scopes: all_scopes - ['write_customers'])

      get "/api/v1/accounts/#{account.id}/inclamo/shopify/connection", headers: admin.create_new_auth_token

      actions = response.parsed_body['actions'].index_by { |action| action['name'] }
      expect(actions.slice('customer_tags', 'customer_note').values).to all(include('available' => false, 'reason' => 'missing_scope', 'missing_scopes' => ['write_customers']))
      expect(actions.slice('order_tags', 'order_note').values).to all(include('available' => true))
    end
  end

  describe "the panel's can map" do
    it 'lets an administrator change order and customer marks when the app holds both scopes' do
      connect!

      expect(panel['can']).to eq('order_marks' => true, 'customer_marks' => true)
    end

    it 'gives an agent without the role nothing to change, and shows the marks' do
      connect!

      body = panel(agent)

      expect(body['can']).to eq('order_marks' => false, 'customer_marks' => false)
      expect(body['customer']['tags']).to include('wholesale')
    end

    it 'keeps customer marks unchangeable without write_customers' do
      connect!(scopes: all_scopes - ['write_customers'])

      expect(panel['can']).to eq('order_marks' => true, 'customer_marks' => false)
    end

    it 'is all false when no store is connected' do
      get "#{base}/panel", headers: admin.create_new_auth_token

      expect(response.parsed_body['can']).to eq('order_marks' => false, 'customer_marks' => false)
    end
  end

  describe 'changing marks' do
    before { connect! }

    it "adds a customer's tag for an administrator" do
      stub_shopify(:customer_marks, data: { customer: customer })
      stub_shopify(:tags_add, data: shopify_fixture('tags_add_customer'))

      post "#{base}/actions", params: { action_name: 'customer_tags', action_id: 'action-ctag-0001', customer_id: customer['id'], params: { operation: 'add', tag: 'vip' } },
                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('outcome' => 'accepted', 'action' => 'customer_tags', 'customer_id' => customer['id'])
    end

    it "replaces an order's note, taking the text from the request and keeping none of it" do
      stub_shopify(:order_details, data: { order: shopify_fixture('order_details_open')['order'] })
      update = stub_shopify(:order_note_update, data: shopify_fixture('order_note_update'))

      post "#{base}/actions", params: { action_name: 'order_note', action_id: 'action-onote-0001', order_id: shopify_fixture('order_details_open').dig('order', 'id'), note: 'Customer asked for delivery after 6 pm' },
                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(update.with { |r| JSON.parse(r.body).dig('variables', 'input', 'note') == 'Customer asked for delivery after 6 pm' }).to have_been_requested.once
      expect(response.body).not_to include('6 pm')
    end

    it 'is forbidden for an agent without the role' do
      post "#{base}/actions", params: { action_name: 'order_tags', action_id: 'action-otag-0001', order_id: order['id'], params: { operation: 'add', tag: 'x' } },
                              headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it "answers the store's refusal with its reason" do
      stub_shopify(:order_details, data: { order: shopify_fixture('order_details_open')['order'] })
      stub_shopify(:tags_add, data: shopify_fixture('tags_add_refused'))

      post "#{base}/actions", params: { action_name: 'order_tags', action_id: 'action-otag-0002', order_id: shopify_fixture('order_details_open').dig('order', 'id'), params: { operation: 'add', tag: 'x' * 300 } },
                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('refusal' => 'store_refused', 'store_message' => 'Order tags is invalid')
    end
  end

  describe 'reading marks past the cache' do
    before { connect! }

    it "reads an order's tags and note from the store every time" do
      marks = stub_shopify(:order_marks, data: { order: order })

      2.times { get "#{base}/marks", params: { order_id: order['id'] }, headers: agent.create_new_auth_token }

      expect(response.parsed_body).to eq('id' => order['id'], 'tags' => order['tags'], 'note' => order['note'])
      expect(marks).to have_been_requested.twice
    end

    it "reads a customer's tags and note" do
      stub_shopify(:customer_marks, data: { customer: customer })

      get "#{base}/marks", params: { customer_id: customer['id'] }, headers: agent.create_new_auth_token

      expect(response.parsed_body).to include('tags' => customer['tags'], 'note' => 'Pays by invoice')
    end

    it "does not read a customer's marks in the limited mode" do
      Inclamo::ShopifyConnection.find_by(account_id: account.id).update!(customer_data_mode: 'limited')

      get "#{base}/marks", params: { customer_id: customer['id'] }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end
end
