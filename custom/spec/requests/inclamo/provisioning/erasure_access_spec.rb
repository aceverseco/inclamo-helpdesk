# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/erasure_requests')

# Who may ask to erase a store (docs/app-store-erasure.md §1, §2): the same
# channel, signature, time window and request-id rule as the store app's
# other calls, and nothing at all where the operator set no secret.
RSpec.describe 'App store erasure: who is asking', type: :request do
  include ProvisioningRequests
  include ErasureRequests

  def nothing_scheduled
    expect(provisioned).to have_attributes(state: 'suspended', erase_after: nil)
    expect(Inclamo::ErasureRequest.count).to eq(0)
  end

  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'unauthorized')
    expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
  end

  context 'without the shared secret (a self-hosted installation)' do
    it 'answers the address as not found, whatever the signature, and schedules nothing' do
      account = create(:account, status: :suspended)
      Inclamo::Provisioning.link!(ProvisioningRequests::STORE, account.id)

      [{}, { secret: 'another-secret-0123456789abcdef-0123456789abcdef' }].each do |options|
        ask_erasure(**options)
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('unauthorized')
        expect(response.headers['X-Inclamo-Provisioning']).to be_nil
      end
      nothing_scheduled
      expect(Inclamo::ProvisioningEvent.count).to eq(0)
    end
  end

  context 'with the shared secret' do
    include_context 'with app provisioning'

    before { suspended_store }

    it 'routes the request' do
      expect(Rails.application.routes.recognize_path(provisioning_path(ProvisioningRequests::STORE, '/erasure'), method: 'POST'))
        .to include(controller: 'inclamo/provisioning/erasures', action: 'create', shop_domain: ProvisioningRequests::STORE)
      expect(Inclamo::Provisioning::ADDRESSES.fetch('/erasure')).to eq('POST' => :erasure)
    end

    it 'refuses a signature made with another secret' do
      ask_erasure(secret: 'another-secret-0123456789abcdef-0123456789abcdef')

      expect_unauthorized
      nothing_scheduled
    end

    it 'refuses a signature made for another call or another store' do
      ask_erasure(signed_as: ['POST', provisioning_path(ProvisioningRequests::STORE, '/removal')])
      expect_unauthorized
      ask_erasure(signed_as: ['POST', provisioning_path('other-store.myshopify.com', '/erasure')])
      expect_unauthorized
      nothing_scheduled
    end

    it 'refuses a stale or a future timestamp' do
      ask_erasure(timestamp: 301.seconds.ago.to_i)
      expect_unauthorized
      ask_erasure(timestamp: 301.seconds.from_now.to_i)
      expect_unauthorized
      nothing_scheduled
    end

    it 'refuses a request without a signature' do
      post provisioning_path(ProvisioningRequests::STORE, '/erasure'), params: '{"contract":1}', headers: { 'CONTENT_TYPE' => 'application/json' }

      expect_unauthorized
      nothing_scheduled
    end

    it 'refuses a request id used for another body, and answers a repetition from the stored answer' do
      request_id = SecureRandom.uuid
      ask_erasure(request_id: request_id)
      expect(response.parsed_body['state']).to eq('scheduled')
      first = response.parsed_body

      ask_erasure(request_id: request_id, body: '{"contract":1, "again":true}')
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'request_id_reused')
      expect(response.headers['X-Inclamo-Provisioning']).to eq('1')

      expect { ask_erasure(request_id: request_id) }.not_to change(Inclamo::ErasureRequest, :count)
      expect(response.parsed_body).to eq(first)
      expect(Inclamo::ErasureRequest.count).to eq(1)
    end

    it 'records every refused attempt' do
      ask_erasure(secret: 'another-secret-0123456789abcdef-0123456789abcdef')
      ask_erasure(body: { contract: 2 })

      expect(events_of.last(2)).to eq(%w[refused refused])
    end
  end
end
