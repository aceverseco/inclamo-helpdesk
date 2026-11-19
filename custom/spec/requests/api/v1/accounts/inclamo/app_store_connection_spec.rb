# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/store_key_stubs')

# The connection page's API for an account the store app provisioned: the
# connection is the app's, made through it, read and checked again by an
# administrator, never replaced or removed by hand.
RSpec.describe 'Inclamo Shopify connection API, through the store app', type: :request do
  include_context 'with the store app for keys'

  let(:account) { provisioned_account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/shopify/connection" }
  let(:credentials) { { shop_domain: 'other-store.myshopify.com', client_id: 'client-id', client_secret: 'client-secret-do-not-leak' } }

  def a_store_that_answers(domain = StoreKeyStubs::STORE)
    stub_shopify(:shop_identity, data: { shop: { name: 'Example Store', myshopifyDomain: domain, currencyCode: 'EUR' } })
    stub_shopify(:customer_data_probe, data: { orders: { nodes: [] }, customers: { nodes: [] } })
  end

  def call(method, url = path, as: admin, params: nil)
    public_send(method, url, params: params, headers: as.create_new_auth_token, as: :json)
    response
  end

  describe 'connecting through the app' do
    it 'connects with a key from the app, nobody entering anything, and shows the store and its actions' do
      stub_store_key(key_answer(scopes: %w[read_customers read_orders write_orders]))
      a_store_that_answers

      call(:post, params: { via: 'app' })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('connected' => true, 'auth_kind' => 'app_key', 'managed_by_app' => true, 'through_app' => true,
                                              'shop_name' => 'Example Store', 'shop_domain' => StoreKeyStubs::STORE, 'status' => 'working')
      available = response.parsed_body['actions'].select { |action| action['available'] }.pluck('name')
      expect(available).to eq(%w[cancel refund address order_tags order_note])
      expect(response.parsed_body['actions'].find { |action| action['name'] == 'discount' }).to include('missing_scopes' => %w[write_discounts])
    end

    it 'says the app answered for another store, and saves nothing' do
      stub_store_key(key_answer(domain: 'another-store.myshopify.com'))

      call(:post, params: { via: 'app' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'other_store', 'message' => 'The Inclamo app answered for another store.')
      expect(Inclamo::ShopifyConnection.where(account_id: account.id)).to be_empty
    end

    it 'names a missing read scope as a permission of the Inclamo app, and saves nothing' do
      stub_store_key(key_answer(scopes: %w[read_customers write_orders]))

      call(:post, params: { via: 'app' })

      expect(response.parsed_body).to include('error' => 'missing_scopes', 'missing_scopes' => %w[read_orders])
      expect(response.parsed_body['message']).to eq('The Inclamo app does not have this permission at your store: read_orders.')
      expect(Inclamo::ShopifyConnection.where(account_id: account.id)).to be_empty
    end

    it 'says the app did not answer, and saves nothing' do
      stub_request(:post, store_key_url).to_timeout

      call(:post, params: { via: 'app' })

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['error']).to eq('app_unavailable')
    end

    it 'is not offered to an account the app did not provision' do
      operators = create(:account)
      operator_admin = create(:user, account: operators, role: :administrator)
      key = stub_store_key

      get "/api/v1/accounts/#{operators.id}/inclamo/shopify/connection", headers: operator_admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('connected' => false, 'managed_by_app' => false, 'through_app' => false)

      post "/api/v1/accounts/#{operators.id}/inclamo/shopify/connection", params: { via: 'app' }, headers: operator_admin.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to eq('not_through_app')
      expect(key).not_to have_been_requested
    end

    it 'is refused to an agent' do
      key = stub_store_key

      expect(call(:post, as: agent, params: { via: 'app' })).to have_http_status(:forbidden)
      expect(key).not_to have_been_requested
    end
  end

  describe 'the connection belongs to the app' do
    let!(:record) { app_key_connection(account) }

    it 'refuses credentials of an app of their own, another store and removal to an administrator, and leaves the connection' do
      graphql = stub_request(:post, /myshopify\.com/)

      expect(call(:post, params: credentials)).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('managed_by_app')
      expect(call(:post, params: credentials.merge(shop_domain: StoreKeyStubs::STORE))).to have_http_status(:forbidden)
      expect(call(:delete)).to have_http_status(:forbidden)

      expect(record.reload).to have_attributes(auth_kind: 'app_key', shop_domain: StoreKeyStubs::STORE, access_token: StoreKeyStubs::KEY)
      expect(graphql).not_to have_been_requested
    end

    it 'lets an administrator check it again with a new key' do
      stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY, scopes: %w[read_customers read_orders write_order_edits]))
      a_store_that_answers

      expect(call(:post, "#{path}/recheck")).to have_http_status(:ok)

      expect(response.parsed_body['actions'].find { |action| action['name'] == 'edit_items' }).to include('available' => true)
      expect(record.reload.access_token).to eq(StoreKeyStubs::NEW_KEY)
    end

    it 'tells an administrator to install the app again when the store does not have it, and to contact support on a mismatch' do
      stub_store_key(key_refusal(404, 'store_not_installed'), key_refusal(403, 'account_mismatch'))

      call(:post, "#{path}/recheck")
      expect(response.parsed_body).to include('error' => 'app_removed')
      expect(response.parsed_body['message']).to include('Install it again in Shopify')
      expect(call(:get).parsed_body).to include('status' => 'broken', 'broken_reason' => 'app_removed')

      call(:post, "#{path}/recheck")
      expect(response.parsed_body['message']).to include('Contact support')
      expect(record.reload.broken_reason).to eq('account_mismatch')
    end

    it 'lets an agent read the store, its scopes and the last check, and nothing more' do
      key = stub_store_key

      expect(call(:get, as: agent)).to have_http_status(:ok)
      expect(response.parsed_body).to include('shop_domain' => StoreKeyStubs::STORE, 'scopes' => record.scopes, 'auth_kind' => 'app_key')
      expect(response.parsed_body['last_checked_at']).to be_present
      expect(call(:post, "#{path}/recheck", as: agent)).to have_http_status(:forbidden)
      expect(call(:delete, as: agent)).to have_http_status(:forbidden)
      expect(call(:post, as: agent, params: credentials)).to have_http_status(:forbidden)
      expect(key).not_to have_been_requested
    end

    it 'never shows the key, in the answer or in the panel' do
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: admin)
      conversation = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
      stub_shopify(:customers_search, data: { customers: { nodes: [] } })

      shown = [call(:get).body, call(:get, "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}/panel").body]

      expect(response.parsed_body['connection']).to include('auth_kind' => 'app_key', 'renewed_at' => be_present)
      expect(shown.join).not_to include(StoreKeyStubs::KEY)
      expect(JSON.parse(shown.first).keys).not_to include('access_token', 'client_secret', 'client_id')
      expect(JSON.parse(shown.first)).to include('renewed_at' => be_present, 'last_checked_at' => be_present)
    end
  end

  describe 'an account the app did not provision' do
    let(:operators) { create(:account) }
    let(:operator_admin) { create(:user, account: operators, role: :administrator) }
    let(:operator_path) { "/api/v1/accounts/#{operators.id}/inclamo/shopify/connection" }

    it 'connects with credentials and removes its connection as before' do
      stub_token_exchange(token: 'token-do-not-leak')
      stub_shopify(:shop_info, data: shop_info_data)
      stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

      post operator_path, params: credentials.merge(shop_domain: 'example-store.myshopify.com'), headers: operator_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('auth_kind' => 'client_credentials', 'managed_by_app' => false)

      delete operator_path, headers: operator_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Inclamo::ShopifyConnection.where(account_id: operators.id)).to be_empty
    end
  end

  describe 'a direct request for an action the key does not allow' do
    it 'is refused naming the scope, and Shopify receives no request' do
      app_key_connection(account, scopes: %w[read_customers read_orders write_orders])
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: admin)
      conversation = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
      graphql = stub_request(:post, /myshopify\.com/)

      post "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}/actions",
           params: { action_name: 'discount', action_id: 'discount-without-scope', params: { preset_id: 1 } },
           headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('outcome' => 'refused', 'refusal' => 'missing_scope')
      expect(Inclamo::ShopifyConnection.find_by(account_id: account.id).missing_scopes_for('discount')).to eq(%w[write_discounts])
      expect(graphql).not_to have_been_requested
    end
  end
end
