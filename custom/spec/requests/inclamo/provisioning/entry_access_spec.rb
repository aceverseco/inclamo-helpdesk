# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/entry_requests')

# Who may ask for a staff member's entry (docs/app-admin-entry.md §1): the
# address exists only where provisioning is on, opens only to the store app's
# signature, and takes a request id once.
RSpec.describe 'App admin entry: who is asking', type: :request do
  include EntryRequests

  context 'without the shared secret (a self-hosted installation)' do
    it 'answers the entry request and the one-time address as addresses that do not exist' do
      expect(Inclamo::Provisioning).not_to be_enabled

      ask_entry
      expect(response).to have_http_status(:not_found)
      expect(response.headers['X-Inclamo-Provisioning']).to be_nil
      expect(response.body).not_to include('entry_url')

      get "/inclamo/entry/#{SecureRandom.urlsafe_base64(32)}"
      expect(response).to have_http_status(:not_found)
      expect(response.headers['set-cookie'].to_s).not_to include('cw_d_session_info')
      expect(Inclamo::ProvisioningEvent.count).to eq(0)
    end

    it 'keeps the password login as it is' do
      user = create(:user, password: 'Password1!')

      post '/auth/sign_in', params: { email: user.email, password: 'Password1!' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers['access-token']).to be_present
    end
  end

  context 'with the shared secret' do
    include_context 'with app admin entry'

    let!(:account) { store_account }

    before { member(account, 'alex@example.test', role: :administrator) }

    it 'routes the call next to the other provisioning calls, and the one-time address' do
      expect(Rails.application.routes.recognize_path(provisioning_path(ProvisioningRequests::STORE, '/entry'), method: 'POST'))
        .to include(controller: 'inclamo/provisioning/entries', action: 'create', shop_domain: ProvisioningRequests::STORE)
      expect(Rails.application.routes.recognize_path('/inclamo/entry', method: 'GET')).to include(controller: 'inclamo/entry', action: 'show')

      ask_entry
      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
    end

    it 'refuses a signature made with another secret, a stale time and a request signed for another call, saying not which' do
      [
        -> { ask_entry(secret: 'another-secret-0123456789abcdef-0123456789abcdef') },
        -> { ask_entry(timestamp: 10.minutes.ago.to_i) },
        -> { ask_entry(signed_as: ['GET', provisioning_path]) },
        -> { ask_entry(request_id: 'not-a-uuid') }
      ].each do |call|
        call.call
        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body).to eq('error' => 'unauthorized')
        expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
      end
      expect(entry_keys).to be_empty
      expect(outcomes.last(4)).to eq(%w[entry_refused] * 4)
    end

    describe 'the request id' do
      let(:request_id) { SecureRandom.uuid }

      def expect_reused
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body).to eq('error' => 'request_id_reused')
        expect(response.body).not_to include('entry_url')
      end

      it 'refuses an answered request sent again unchanged, and no second address exists' do
        timestamp = Time.now.to_i
        ask_entry(request_id: request_id, timestamp: timestamp)
        expect(response).to have_http_status(:ok)
        expect(entry_keys.size).to eq(1)

        ask_entry(request_id: request_id, timestamp: timestamp)

        expect_reused
        expect(entry_keys.size).to eq(1)
        expect(Inclamo::ProvisioningEvent.where(request_id: request_id).pluck(:outcome)).to eq(%w[entry_given entry_refused])
      end

      it 'refuses the id with another body, and an id an earlier refusal used' do
        ask_entry(request_id: request_id, staff: { email: 'nobody@example.test' })
        expect(response).to have_http_status(:forbidden)

        ask_entry(request_id: request_id)
        expect_reused

        other_id = SecureRandom.uuid
        ask_entry(request_id: other_id, body: { contract: 2 })
        expect(response).to have_http_status(:unprocessable_entity)
        ask_entry(request_id: other_id)
        expect_reused
        expect(entry_keys).to be_empty
      end

      it 'keeps the id taken for ten minutes, without the answer' do
        ask_entry(request_id: request_id)
        key = Inclamo::Provisioning::RequestStore.key(request_id)

        expect(Redis::Alfred.ttl(key)).to be_between(590, 600)
        expect(Redis::Alfred.get(key)).not_to include('entry_url')
        expect(Redis::Alfred.get(key)).not_to include('/inclamo/entry/')
      end

      it 'refuses an id of another provisioning call, and the other calls refuse an id of this one' do
        ask_status(request_id: request_id)
        ask_entry(request_id: request_id)
        expect_reused

        entry_id = SecureRandom.uuid
        ask_entry(request_id: entry_id)
        ask_status(request_id: entry_id)
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body).to eq('error' => 'request_id_reused')
      end

      it 'leaves the other provisioning calls answering a repeated id from the stored answer' do
        provision(request_id: request_id)
        first = response.parsed_body

        provision(request_id: request_id)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(first)
      end

      it 'checks the signature first: a reused id under a wrong signature is unauthorised' do
        ask_entry(request_id: request_id)

        ask_entry(request_id: request_id, secret: 'another-secret-0123456789abcdef-0123456789abcdef')

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
