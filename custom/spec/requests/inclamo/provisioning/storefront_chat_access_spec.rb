# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App storefront chat: the provisioning channel\'s rules', type: :request do
  include ProvisioningRequests

  let(:other_secret) { 'another-secret-0123456789abcdef-0123456789abcdef' }

  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'unauthorized')
  end

  context 'without the shared secret (a self-hosted installation)' do
    it 'answers both addresses as not found, whatever the signature, and creates nothing' do
      account = create(:account)
      Inclamo::ProvisionedAccount.create!(shop_domain: ProvisioningRequests::STORE, account: account)
      expect(Inclamo::Provisioning).not_to be_enabled

      [-> { ask_for_chat }, -> { ask_chat_status }].each do |call|
        expect { call.call }.to not_change(Inbox, :count).and not_change(Inclamo::ProvisioningEvent, :count)
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to match(/unauthorized|no_account|no_storefront_chat/)
        expect(response.headers['X-Inclamo-Provisioning']).to be_nil
      end
      expect(storefront_inbox).to be_nil
    end
  end

  context 'with the shared secret' do
    include_context 'with app provisioning'

    let!(:account) { linked_account }

    it 'routes the two calls' do
      path = provisioning_path(ProvisioningRequests::STORE, '/storefront-chat')

      { 'PUT' => 'update', 'GET' => 'show' }.each do |verb, action|
        expect(Rails.application.routes.recognize_path(path, method: verb))
          .to include(controller: 'inclamo/provisioning/storefront_chats', action: action, shop_domain: ProvisioningRequests::STORE)
      end
      %w[POST DELETE PATCH].each do |verb|
        expect { Rails.application.routes.recognize_path(path, method: verb) }.to raise_error(ActionController::RoutingError)
      end
    end

    it 'refuses a signature made with another secret, and the account has no new inbox' do
      expect { ask_for_chat(secret: other_secret) }.to not_change(Inbox, :count)
      expect_unauthorized
      expect(Inclamo::ProvisioningEvent.order(:id).last).to have_attributes(outcome: 'refused', shop_domain: ProvisioningRequests::STORE)

      ask_chat_status(secret: other_secret)
      expect_unauthorized
      expect(storefront_inbox).to be_nil
    end

    it 'refuses a request without a signature, a stale one, and one signed for another call' do
      put provisioning_path(ProvisioningRequests::STORE, '/storefront-chat'), params: '{"contract":1}', headers: { 'CONTENT_TYPE' => 'application/json' }
      expect_unauthorized
      ask_for_chat(timestamp: 10.minutes.ago.to_i)
      expect_unauthorized
      # The path is signed whole: the signature of the account's call, or of
      # the status call, does not open this one.
      ask_for_chat(signed_as: ['PUT', provisioning_path])
      expect_unauthorized
      ask_for_chat(signed_as: ['GET', provisioning_path(ProvisioningRequests::STORE, '/storefront-chat')])
      expect_unauthorized
      ask_chat_status(signed_as: ['GET', provisioning_path])
      expect_unauthorized

      expect(storefront_inbox).to be_nil
    end

    it 'accepts the previous secret while the app is being switched over' do
      with_modified_env INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS: other_secret do
        ask_for_chat(secret: other_secret)
        expect(response).to have_http_status(:created)
      end
    end

    it 'refuses a request id already used for another request as reused' do
      request_id = SecureRandom.uuid
      ask_for_chat(request_id: request_id)
      expect(response).to have_http_status(:created)

      ask_for_chat(request_id: request_id, with: { storefront_url: 'https://another-address.example' })
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'request_id_reused')
      ask_chat_status(request_id: request_id)
      expect(response.parsed_body).to eq('error' => 'request_id_reused')
      # The account's own call is another request too.
      provision(request_id: request_id)
      expect(response.parsed_body).to eq('error' => 'request_id_reused')
      expect(Inbox.where(account_id: account.id).count).to eq(1)
    end

    it 'signs the request id: a captured request sent again under another id is refused' do
      ask_for_chat(request_id: SecureRandom.uuid, signed_id: SecureRandom.uuid)

      expect_unauthorized
      expect(storefront_inbox).to be_nil
    end

    it 'tells a repetition still being answered to try again' do
      request_id = SecureRandom.uuid
      body = JSON.generate(contract: 1)
      path = provisioning_path(ProvisioningRequests::STORE, '/storefront-chat')
      Inclamo::Provisioning::RequestStore.reserve(request_id, Inclamo::Provisioning::RequestStore.digest(method: 'PUT', path: path, body: body))
      stub_const('Inclamo::Provisioning::StoresController::PENDING_WAIT', 0.2)

      ask_for_chat(body: body, request_id: request_id)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'in_progress')
      expect(response.headers['Retry-After']).to eq('1')
      expect(storefront_inbox).to be_nil
    end

    it 'marks every answer of both addresses as provisioning\'s' do
      ask_chat_status
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([404, '1'])
      ask_for_chat(body: { contract: 2 })
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([422, '1'])
      ask_for_chat(secret: other_secret)
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([401, '1'])
      ask_for_chat
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([201, '1'])
      ask_chat_status
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([200, '1'])
      ask_for_chat('unknown-store.myshopify.com')
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([404, '1'])
      remove_app
      ask_for_chat
      expect([response.status, response.headers['X-Inclamo-Provisioning']]).to eq([409, '1'])
      expect(response.parsed_body).to eq('error' => 'account_suspended')
    end

    context 'with the request limits on' do
      # As in limits_spec.rb: Rack::Attack on, an outside address, counters in memory.
      let(:outside) { { 'REMOTE_ADDR' => '203.0.113.9' } }

      around do |example|
        enabled = Rack::Attack.enabled
        store = Rack::Attack.cache.store
        Rack::Attack.enabled = true
        Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
        with_modified_env(INCLAMO_APP_PROVISIONING_PUT_LIMIT: '30', INCLAMO_APP_PROVISIONING_STORE_LIMIT: '2',
                          INCLAMO_APP_PROVISIONING_GET_LIMIT: '2') { example.run }
      ensure
        Rack::Attack.cache.store = store
        Rack::Attack.enabled = enabled
      end

      def expect_limited
        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body).to eq('error' => 'rate_limited')
        expect(response.headers['Retry-After'].to_i).to be_between(1, 3600)
      end

      it 'answers requests over the store\'s limit with the time to try again, and creates nothing for them' do
        ask_for_chat(headers: outside)
        expect(response).to have_http_status(:created)
        storefront_inbox.destroy!
        ask_for_chat(headers: outside)
        expect(response).to have_http_status(:created)
        storefront_inbox.destroy!

        expect { ask_for_chat(headers: outside) }.to not_change(Inbox, :count)
        expect_limited
        expect(storefront_inbox).to be_nil
        expect(Inclamo::ProvisioningEvent.order(:id).last).to have_attributes(outcome: 'limited', shop_domain: ProvisioningRequests::STORE)
      end

      it 'counts the request with the account\'s own: one store has one allowance for both' do
        provision('second-store.myshopify.com', headers: outside)
        expect(response).to have_http_status(:created)
        ask_for_chat('second-store.myshopify.com', headers: outside)
        expect(response).to have_http_status(:ok)

        ask_for_chat('second-store.myshopify.com', headers: outside)
        expect_limited
        provision('second-store.myshopify.com', headers: outside)
        expect_limited

        # Another store is not held back by it.
        ask_for_chat(headers: outside)
        expect(response).to have_http_status(:created)
      end

      it 'counts the request against the installation\'s limit too' do
        with_modified_env INCLAMO_APP_PROVISIONING_PUT_LIMIT: '2', INCLAMO_APP_PROVISIONING_STORE_LIMIT: '5' do
          provision('second-store.myshopify.com', headers: outside)
          ask_for_chat(headers: outside)
          expect(response).to have_http_status(:created)

          ask_for_chat('second-store.myshopify.com', headers: outside)
          expect_limited
        end
      end

      it 'limits the status call with the channel\'s other status calls' do
        ask_chat_status(headers: outside)
        expect(response).to have_http_status(:not_found)
        ask_status(headers: outside)
        expect(response).to have_http_status(:ok)

        ask_chat_status(headers: outside)
        expect_limited
        ask_for_chat(headers: outside)
        expect(response).to have_http_status(:created)
      end

      it 'does not count a request answered from its stored answer' do
        request_id = SecureRandom.uuid
        3.times do
          ask_for_chat(request_id: request_id, headers: outside)
          expect(response).to have_http_status(:created)
        end
        status_id = SecureRandom.uuid
        3.times do
          ask_chat_status(request_id: status_id, headers: outside)
          expect(response).to have_http_status(:ok)
        end

        provision(headers: outside)
        expect(response).to have_http_status(:ok)
        ask_for_chat(headers: outside)
        expect_limited
        ask_status(headers: outside)
        expect(response).to have_http_status(:ok)
        ask_chat_status(headers: outside)
        expect_limited
      end

      it 'does not count requests that are not the app\'s' do
        4.times do
          ask_for_chat(headers: outside, secret: other_secret)
          expect_unauthorized
          ask_chat_status(headers: outside, secret: other_secret)
          expect_unauthorized
        end

        ask_for_chat(headers: outside)
        expect(response).to have_http_status(:created)
        ask_chat_status(headers: outside)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
