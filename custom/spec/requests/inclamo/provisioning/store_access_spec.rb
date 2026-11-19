# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')
require Rails.root.join('custom/spec/support/store_key_stubs')

# An account the store app provisions gets its store connection through the
# app (docs/app-store-access.md): after it is created or restored, in the
# background, so the app's answer never waits for it; the key goes when the
# account is suspended.
RSpec.describe 'App store access: the connection of a provisioned account', type: :request do
  include_context 'with app provisioning'
  include_context 'with the store app for keys'

  let(:account) { provisioned.account }

  def connection
    Inclamo::ShopifyConnection.find_by(account_id: account.id)
  end

  def a_store_that_answers
    stub_shopify(:shop_identity, data: { shop: { name: 'Example Store', myshopifyDomain: StoreKeyStubs::STORE, currencyCode: 'EUR' } })
    stub_shopify(:customer_data_probe, data: { orders: { nodes: [] }, customers: { nodes: [] } })
  end

  describe 'making the connection' do
    it 'is asked for after a created account, in the background, and the answer does not wait for it' do
      key = stub_store_key

      expect { provision }.to have_enqueued_job(Inclamo::StoreAccessJob).with(kind_of(Integer))

      expect(response).to have_http_status(:created)
      expect(key).not_to have_been_requested
      expect(connection).to be_nil
    end

    it 'is asked for after a restored account, and not after one that existed or a repeated request' do
      provision
      remove_app
      request_id = SecureRandom.uuid

      expect { provision(request_id: request_id) }.to have_enqueued_job(Inclamo::StoreAccessJob).with(account.id)
      expect(response.parsed_body['outcome']).to eq('restored')
      expect { provision(request_id: request_id) }.not_to have_enqueued_job(Inclamo::StoreAccessJob)
      expect { provision }.not_to have_enqueued_job(Inclamo::StoreAccessJob)
      expect(response.parsed_body['outcome']).to eq('existed')
    end

    it 'saves the connection through the app once the step has run' do
      stub_store_key(key_answer(scopes: %w[read_customers read_orders write_orders]))
      a_store_that_answers

      perform_enqueued_jobs(only: Inclamo::StoreAccessJob) { provision }

      expect(connection).to have_attributes(auth_kind: 'app_key', status: 'working', shop_domain: StoreKeyStubs::STORE, shop_name: 'Example Store',
                                            scopes: %w[read_customers read_orders write_orders], client_id: nil, client_secret: nil,
                                            access_token: StoreKeyStubs::KEY)
      expect(connection.renewed_at).to be_within(1.minute).of(Time.current)
      expect(Inclamo::ProvisioningEvent.where(account_id: account.id).pluck(:outcome)).to eq(%w[key_granted])
    end

    it 'leaves the account without a connection when the step fails, and the account answers as created' do
      stub_request(:post, store_key_url).to_timeout

      perform_enqueued_jobs(only: Inclamo::StoreAccessJob) { provision }

      expect(response).to have_http_status(:created)
      expect(account).to be_active
      expect(connection).to be_nil
    end

    it "saves nothing for a key to another store, one without a read scope, or the app's refusal" do
      provision
      a_store_that_answers
      [key_answer(domain: 'another-store.myshopify.com'), key_answer(scopes: %w[read_customers write_orders]), key_refusal(404, 'store_not_installed')].each do |answer|
        stub_store_key(answer)

        Inclamo::StoreAccessJob.perform_now(account.id)

        expect(connection).to be_nil
      end
    end

    it 'leaves a connection made by hand before as it is' do
      provision
      hand_made = create(:inclamo_shopify_connection, account: account)
      key = stub_store_key

      Inclamo::StoreAccessJob.perform_now(account.id)

      expect(hand_made.reload).to be_client_credentials
      expect(key).not_to have_been_requested
    end
  end

  describe 'suspension' do
    it 'deletes the key and its scopes, and keeps the connection record and the order action records' do
      provision
      record = app_key_connection(account)
      action = Inclamo::OrderAction.create!(account: account, action_id: 'refund-before-suspension', action: 'refund', order_id: 'gid://shopify/Order/1',
                                            order_number: '#1001', outcome: 'accepted', completed_at: 1.day.ago)

      remove_app

      expect(record.reload).to have_attributes(access_token: nil, token_expires_at: nil, scopes: [], auth_kind: 'app_key')
      expect(Inclamo::OrderAction.find(action.id)).to have_attributes(outcome: 'accepted', order_number: '#1001')
      row = Inclamo::ShopifyConnection.connection.select_one("SELECT access_token FROM inclamo_shopify_connections WHERE id = #{record.id}")
      expect(row['access_token']).to be_nil
    end

    it 'leaves the key of a connection made by hand' do
      provision
      record = create(:inclamo_shopify_connection, account: account)

      remove_app

      expect(record.reload.access_token).to eq('token-for-specs')
    end

    it 'is followed by a new key when the account is restored' do
      provision
      record = app_key_connection(account)
      remove_app
      stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY))
      a_store_that_answers

      perform_enqueued_jobs(only: Inclamo::StoreAccessJob) { provision }

      expect(record.reload).to have_attributes(access_token: StoreKeyStubs::NEW_KEY, status: 'working')
    end
  end

  describe 'an installation that cannot ask the app' do
    {
      'the app address' => { INCLAMO_APP_URL: nil },
      'an HTTPS address' => { INCLAMO_APP_URL: 'http://app.example.test/helpdesk' }
    }.each do |missing, env|
      it "has the account without a connection and sends no request without #{missing}" do
        key = stub_request(:post, /store-key/)

        with_modified_env(**env) do
          expect { provision }.not_to have_enqueued_job(Inclamo::StoreAccessJob)
          Inclamo::StoreAccessJob.perform_now(account.id)
        end

        expect(response).to have_http_status(:created)
        expect(connection).to be_nil
        expect(key).not_to have_been_requested
      end
    end

    it 'sends no request without encryption keys' do
      key = stub_request(:post, /store-key/)
      provision
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      Inclamo::StoreAccessJob.perform_now(account.id)

      expect(connection).to be_nil
      expect(key).not_to have_been_requested
    end

    it "uses the store's own address when the app gave one, also without the installation's" do
      own = 'https://other-app.example.test/keys'
      stub_store_key(address: own)
      a_store_that_answers

      with_modified_env(INCLAMO_APP_URL: nil) do
        perform_enqueued_jobs(only: Inclamo::StoreAccessJob) { provision(store_access_url: own) }
      end

      expect(connection).to be_app_key
      expect(a_request(:post, store_key_url(address: own))).to have_been_made.once
    end
  end
end
