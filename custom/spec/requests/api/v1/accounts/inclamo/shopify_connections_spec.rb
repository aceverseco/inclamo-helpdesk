# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo Shopify connection API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/shopify/connection" }
  let(:credentials) { { shop_domain: 'example-store.myshopify.com', client_id: 'client-id', client_secret: 'client-secret-do-not-leak' } }

  def stub_full_store(scopes: nil)
    stub_token_exchange(token: 'token-do-not-leak')
    stub_shopify(:shop_info, data: scopes ? shop_info_data(scopes: scopes) : shop_info_data)
    stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })
  end

  def connect(params = credentials, as: admin)
    post path, params: params, headers: as.create_new_auth_token, as: :json
  end

  describe 'connecting' do
    it 'saves a verified connection and shows the store and its actions' do
      stub_full_store

      connect

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('connected' => true, 'status' => 'working', 'shop_name' => 'Example Store',
                              'shop_domain' => 'example-store.myshopify.com', 'customer_data' => 'full')
      expect(body['actions'].pluck('name', 'available')).to eq([['cancel', true], ['refund', true], ['address', true], ['replacement', true]])
      expect(Inclamo::ShopifyConnection.find_by(account: account)).to be_client_credentials
    end

    it 'saves a legacy token the same way' do
      stub_shopify(:shop_info, data: shop_info_data)
      stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

      connect(shop_domain: 'example-store.myshopify.com', access_token: 'legacy-token-do-not-leak')

      expect(response).to have_http_status(:created)
      expect(Inclamo::ShopifyConnection.find_by(account: account)).to be_legacy_token
    end

    it 'never returns the secret or a token' do
      stub_full_store
      connect

      get path, headers: admin.create_new_auth_token, as: :json

      [response.body, Inclamo::ShopifyConnection.last.attributes.except('client_secret', 'access_token').to_json].each do |text|
        expect(text).not_to include('client-secret-do-not-leak')
        expect(text).not_to include('token-do-not-leak')
      end
      expect(response.parsed_body.keys).not_to include('client_secret', 'access_token', 'client_id')
    end

    it 'keeps the credentials out of the request log' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      expect(filter.filter(client_secret: 'x', access_token: 'y')).to eq(client_secret: '[FILTERED]', access_token: '[FILTERED]')
    end

    it 'says the app must be installed first' do
      stub_token_refusal('app_not_installed')

      connect

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'app_not_installed')
      expect(Inclamo::ShopifyConnection.count).to eq(0)
    end

    it 'says the store refused the credentials' do
      stub_token_refusal('invalid_request')

      connect

      expect(response.parsed_body).to include('error' => 'credentials_refused')
      expect(Inclamo::ShopifyConnection.count).to eq(0)
    end

    it 'names the expected form of the domain and sends nothing to Shopify' do
      connect(credentials.merge(shop_domain: 'shop.example.com'))

      expect(response.parsed_body['error']).to eq('invalid_domain')
      expect(response.parsed_body['message']).to include('myshopify.com')
      expect(WebMock).not_to have_requested(:any, /myshopify|example\.com/)
    end

    it 'names the missing read scope' do
      stub_full_store(scopes: %w[read_customers])

      connect

      expect(response.parsed_body).to include('error' => 'missing_scopes', 'missing_scopes' => %w[read_orders])
      expect(Inclamo::ShopifyConnection.count).to eq(0)
    end

    it 'saves a store that hides customer data as limited' do
      stub_token_exchange
      stub_shopify(:shop_info, data: shop_info_data)
      stub_shopify(:customer_data_probe, errors: access_denied)

      connect

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['customer_data']).to eq('limited')
      expect(body['actions'].find { |action| action['name'] == 'address' }).to include('available' => false, 'reason' => 'customer_data_hidden')
    end

    it 'is refused without encryption keys' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      connect

      expect(response.parsed_body['error']).to eq('encryption_not_configured')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'is forbidden for an agent' do
      connect(as: agent)

      expect(response).to have_http_status(:forbidden)
      expect(Inclamo::ShopifyConnection.count).to eq(0)
    end

    it 'refuses a second store until the first is removed' do
      create(:inclamo_shopify_connection, account: account)

      connect(credentials.merge(shop_domain: 'other-store.myshopify.com'))

      expect(response.parsed_body['error']).to eq('already_connected')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'lets an administrator reconnect the same store with new credentials' do
      create(:inclamo_shopify_connection, account: account, status: 'broken')
      stub_full_store

      connect

      expect(response).to have_http_status(:ok)
      expect(Inclamo::ShopifyConnection.find_by(account: account)).to be_working
    end
  end

  describe 'reading' do
    it 'tells any member that nothing is connected' do
      get path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('connected' => false, 'encryption_configured' => true)
    end

    it 'shows an agent the store, its scopes and the time of the last check' do
      create(:inclamo_shopify_connection, :read_only, account: account)

      get path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body).to include('connected' => true, 'scopes' => %w[read_customers read_orders])
      expect(body['last_checked_at']).to be_present
      expect(body['actions']).to all(include('available' => false, 'reason' => 'missing_scope'))
    end

    it 'does not show the connection of another account' do
      create(:inclamo_shopify_connection)

      get path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['connected']).to be(false)
    end
  end

  describe 'checking again' do
    it 'reads the scopes again after the merchant added one' do
      create(:inclamo_shopify_connection, :read_only, account: account)
      stub_full_store

      post "#{path}/recheck", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['actions'].find { |action| action['name'] == 'cancel' }['available']).to be(true)
    end

    it 'reports a connection the store no longer accepts as broken' do
      create(:inclamo_shopify_connection, account: account)
      stub_token_refusal('app_not_installed')

      post "#{path}/recheck", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['error']).to eq('app_not_installed')
      expect(Inclamo::ShopifyConnection.find_by(account: account)).to be_broken
    end

    it 'is forbidden for an agent' do
      create(:inclamo_shopify_connection, account: account)

      post "#{path}/recheck", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'removing' do
    it 'deletes the credentials and returns to "not connected"' do
      create(:inclamo_shopify_connection, account: account)

      delete path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Inclamo::ShopifyConnection.count).to eq(0)
      get path, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['connected']).to be(false)
    end

    it 'is forbidden for an agent' do
      create(:inclamo_shopify_connection, account: account)

      delete path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Inclamo::ShopifyConnection.count).to eq(1)
    end
  end
end
