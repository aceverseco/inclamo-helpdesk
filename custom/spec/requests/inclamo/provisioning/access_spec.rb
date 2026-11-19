# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: who is asking', type: :request do
  include ProvisioningRequests

  def nothing_created
    expect(Inclamo::ProvisionedAccount.count).to eq(0)
    expect(User.from_email('alex@example.test')).to be_nil
  end

  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'unauthorized')
  end

  context 'without the shared secret (a self-hosted installation)' do
    it 'answers all three addresses as not found, whatever the signature' do
      expect(Inclamo::Provisioning).not_to be_enabled

      [-> { provision }, -> { ask_status }, -> { remove_app }].each do |call|
        call.call
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('unauthorized')
      end
      nothing_created
      expect(Inclamo::ProvisioningEvent.count).to eq(0)
    end

    it 'loads every file of the capability under the name the autoloader expects' do
      %w[custom/lib/inclamo/provisioning custom/app/controllers/inclamo/provisioning].each do |directory|
        expect { Rails.autoloaders.main.eager_load_dir(Rails.root.join(directory).to_s) }.not_to raise_error
      end
    end

    it 'treats a secret shorter than 32 bytes as not set' do
      with_modified_env INCLAMO_APP_PROVISIONING_SECRET: 'too-short' do
        expect(Inclamo::Provisioning).not_to be_enabled
        expect(Inclamo::Provisioning.secrets).to eq([])
      end
    end
  end

  context 'with the shared secret' do
    include_context 'with app provisioning'

    it 'routes the three calls' do
      { 'PUT' => 'update', 'GET' => 'show' }.each do |verb, action|
        expect(Rails.application.routes.recognize_path(provisioning_path, method: verb))
          .to include(controller: 'inclamo/provisioning/stores', action: action, shop_domain: ProvisioningRequests::STORE)
      end
      expect(Rails.application.routes.recognize_path(provisioning_path(ProvisioningRequests::STORE, '/removal'), method: 'POST'))
        .to include(controller: 'inclamo/provisioning/stores', action: 'removal')

      provision
      expect(response).to have_http_status(:created)
      ask_status
      expect(response).to have_http_status(:ok)
      remove_app
      expect(response).to have_http_status(:ok)
    end

    it 'reproduces the worked examples of the contract' do
      secret = 'test-secret-not-for-production-0123456789abcdef'
      path = '/inclamo/provisioning/stores/example-store.myshopify.com'
      body = '{"contract":1,"shop":{"domain":"example-store.myshopify.com","name":"Example Store","locale":"en",' \
             '"timezone":"America/New_York"},"admin":{"email":"alex@example.com","name":"Alex Example","email_verified":true}}'

      expect(Inclamo::Provisioning::Signature.sign(secret, timestamp: 1_794_000_000, method: 'PUT', path: path, body: body))
        .to eq('sha256=022264e7add0f4964389e0bbf7e1703ee0bdd90525e48f21efd9c2e071a551a0')
      expect(Inclamo::Provisioning::Signature.sign(secret, timestamp: 1_794_000_000, method: 'GET', path: path, body: ''))
        .to eq('sha256=87226ebd191b47f07a987e51faa1f2def88e835ea484a1f5092d5a19c94ff2a6')
    end

    it 'accepts a valid request' do
      provision

      expect(response).to have_http_status(:created)
      expect(provisioned).to be_present
    end

    it 'refuses a signature made with another secret' do
      provision(secret: 'another-secret-0123456789abcdef-0123456789abcdef')

      expect_unauthorized
      nothing_created
    end

    it 'refuses a request without its headers, one by one' do
      %w[X-Inclamo-Timestamp X-Inclamo-Request-Id X-Inclamo-Signature].each do |header|
        provision(headers: { header => nil })
        expect_unauthorized
      end
      provision(request_id: 'not-a-uuid')
      expect_unauthorized
      nothing_created
    end

    it 'refuses a stale time and a future time, and accepts one inside the window' do
      provision(timestamp: 10.minutes.ago.to_i)
      expect_unauthorized
      provision(timestamp: 301.seconds.ago.to_i - 2)
      expect_unauthorized
      provision(timestamp: 10.minutes.from_now.to_i)
      expect_unauthorized
      provision(timestamp: 301.seconds.from_now.to_i + 2)
      expect_unauthorized
      nothing_created

      provision(timestamp: 290.seconds.ago.to_i)
      expect(response).to have_http_status(:created)
      ask_status(timestamp: 290.seconds.from_now.to_i)
      expect(response).to have_http_status(:ok)
    end

    it 'refuses a changed body under an unchanged signature' do
      body = JSON.generate(provisioning_body)
      signature = Inclamo::Provisioning::Signature.sign(ProvisioningRequests::SECRET, timestamp: Time.now.to_i, method: 'PUT',
                                                                                     path: provisioning_path, body: body)
      put provisioning_path, params: body.sub('Alex Example', 'Mallory Example'), headers: {
        'CONTENT_TYPE' => 'application/json', 'X-Inclamo-Timestamp' => Time.now.to_i.to_s,
        'X-Inclamo-Request-Id' => SecureRandom.uuid, 'X-Inclamo-Signature' => signature
      }

      expect_unauthorized
      nothing_created
    end

    it 'refuses a signed status request replayed as a removal' do
      provision
      account = provisioned.account

      provisioning_call(:post, suffix: '/removal', signed_as: ['GET', provisioning_path])

      expect_unauthorized
      expect(account.reload).to be_active
      expect(provisioned).to be_active
    end

    it 'refuses a request signed for another store' do
      provisioning_call(:put, 'other-store.myshopify.com', body: provisioning_body('other-store.myshopify.com'),
                                                           signed_as: ['PUT', provisioning_path])

      expect_unauthorized
      nothing_created
    end

    it 'accepts the previous secret while the app is switched over, and not after it is removed' do
      previous = 'previous-secret-0123456789abcdef-0123456789abcdef'

      provision(secret: previous)
      expect_unauthorized

      with_modified_env INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS: previous do
        provision(secret: previous)
        expect(response).to have_http_status(:created)
        ask_status
        expect(response).to have_http_status(:ok)
      end

      ask_status(secret: previous)
      expect_unauthorized
    end

    it 'compares signatures in constant time, against every secret' do
      allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original

      with_modified_env INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS: 'previous-secret-0123456789abcdef-0123456789abcdef' do
        ask_status
      end

      expect(ActiveSupport::SecurityUtils).to have_received(:secure_compare).with(/\Asha256=\h{64}\z/, /\Asha256=\h{64}\z/).twice
    end

    it 'never puts the secret in an answer' do
      [provision, ask_status, remove_app, provision(secret: 'another-secret-0123456789abcdef-0123456789abcdef')].each do |answer|
        expect(answer.body).not_to include(ProvisioningRequests::SECRET)
      end
    end

    describe 'the request id' do
      let(:request_id) { SecureRandom.uuid }

      it 'answers the same id and body from the stored answer, without a second creation' do
        body = provisioning_body
        first = provision(body: body, request_id: request_id)
        expect(first).to have_http_status(:created)
        first_body = first.parsed_body

        expect { provision(body: body, request_id: request_id, timestamp: Time.now.to_i + 5) }
          .to not_change(Account, :count).and not_change(User, :count).and not_change(Inclamo::ProvisionedAccount, :count)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to eq(first_body)
        expect(response.parsed_body['outcome']).to eq('created')
      end

      it 'does not act again: a removal repeated under its id after a restoration leaves the account active' do
        provision
        remove_app(request_id: request_id)
        expect(response.parsed_body).to eq('contract' => 1, 'state' => 'suspended')
        provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
        expect(response.parsed_body['outcome']).to eq('restored')

        remove_app(request_id: request_id)

        expect(response.parsed_body).to eq('contract' => 1, 'state' => 'suspended')
        expect(provisioned.account.reload).to be_active
      end

      it 'keeps the answer for ten minutes' do
        provision(request_id: request_id)
        key = Inclamo::Provisioning::RequestStore.key(request_id)

        expect(Redis::Alfred.ttl(key)).to be_between(590, 600)
      end

      it 'refuses the same id with another body' do
        provision(request_id: request_id)
        account = provisioned.account

        provision(request_id: request_id, shop: { name: 'Renamed Store' })

        expect_unauthorized
        expect(account.reload.name).to eq('Example Store')
      end

      it 'refuses a key reused for another store' do
        provision(request_id: request_id)

        provision('second-store.myshopify.com', request_id: request_id)
        expect_unauthorized
        expect(provisioned('second-store.myshopify.com')).to be_nil

        remove_app('second-store.myshopify.com', request_id: request_id)
        expect_unauthorized
        ask_status('second-store.myshopify.com', request_id: request_id)
        expect_unauthorized
        expect(Inclamo::ProvisionedAccount.count).to eq(1)
      end

      it 'frees an id whose request failed, so the retry acts' do
        allow(AccountBuilder).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)
        provision(request_id: request_id)
        expect(response).to have_http_status(:internal_server_error)
        expect(provisioned).to be_nil

        allow(AccountBuilder).to receive(:new).and_call_original
        provision(request_id: request_id)
        expect(response).to have_http_status(:created)
      end

      it 'tells a repetition that arrives while the first is still being answered to try again' do
        body = JSON.generate(provisioning_body)
        digest = Inclamo::Provisioning::RequestStore.digest(method: 'PUT', path: provisioning_path, body: body)
        expect(Inclamo::Provisioning::RequestStore.reserve(request_id, digest)).to eq(:reserved)
        stub_const('Inclamo::Provisioning::StoresController::PENDING_WAIT', 0.2)

        provision(body: body, request_id: request_id)

        expect(response).to have_http_status(:service_unavailable)
        expect(response.headers['Retry-After']).to eq('1')
        nothing_created
      end
    end
  end
end
