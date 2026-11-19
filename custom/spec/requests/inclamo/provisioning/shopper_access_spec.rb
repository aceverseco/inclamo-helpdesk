# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')

# Who may ask about one shopper (docs/app-store-erasure.md §1, §2): the same
# channel, signature, time window and request-id rule as the store app's other
# calls, and nothing at all where the operator set no secret.
RSpec.describe 'App store erasure: who is asking about a shopper', type: :request do
  include ProvisioningRequests
  include ShopperRequests

  let(:calls) { %i[erasure data_request counts] }

  def call(name, **)
    case name
    when :erasure then ask_shopper_erasure(**)
    when :data_request then ask_data_request(**)
    else ask_shopper_counts(**)
    end
  end

  def nothing_made
    expect(Inclamo::ErasureRequest.count).to eq(0)
    expect(Inclamo::DataRequestInbox.count).to eq(0)
  end

  context 'without the shared secret (a self-hosted installation)' do
    it 'answers each address as not found, whatever the signature, and makes nothing' do
      account = create(:account)
      Inclamo::Provisioning.link!(ProvisioningRequests::STORE, account.id)
      shopper_contact(account)

      calls.each do |name|
        [{}, { secret: 'another-secret-0123456789abcdef-0123456789abcdef' }].each do |options|
          call(name, **options)
          expect(response).to have_http_status(:not_found)
          expect(response.headers['X-Inclamo-Provisioning']).to be_nil
          expect(response.body).not_to include('unauthorized')
        end
      end
      nothing_made
      expect(Inclamo::ProvisioningEvent.count).to eq(0)
    end
  end

  context 'with the shared secret' do
    include_context 'with app provisioning'

    before do
      active_store
      shopper_contact(provisioned.account)
    end

    def expect_unauthorized
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'unauthorized')
      expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
    end

    it 'routes the three addresses, and counts each with its own kind' do
      routes = Rails.application.routes
      expect(routes.recognize_path(provisioning_path(ProvisioningRequests::STORE, '/shoppers/erasure'), method: 'POST'))
        .to include(controller: 'inclamo/provisioning/shopper_requests', action: 'erasure')
      expect(routes.recognize_path(provisioning_path(ProvisioningRequests::STORE, '/shoppers/data-request'), method: 'POST'))
        .to include(controller: 'inclamo/provisioning/shopper_requests', action: 'data_request')
      expect(routes.recognize_path(provisioning_path(ProvisioningRequests::STORE, '/shoppers/requests'), method: 'GET'))
        .to include(controller: 'inclamo/provisioning/shopper_requests', action: 'counts')
      expect(Inclamo::Provisioning::ADDRESSES.slice('/shoppers/erasure', '/shoppers/data-request', '/shoppers/requests'))
        .to eq('/shoppers/erasure' => { 'POST' => :erasure }, '/shoppers/data-request' => { 'POST' => :erasure },
               '/shoppers/requests' => { 'GET' => :get })
    end

    it 'refuses a signature made with another secret' do
      calls.each do |name|
        call(name, secret: 'another-secret-0123456789abcdef-0123456789abcdef')
        expect_unauthorized
      end
      nothing_made
    end

    it 'refuses a signature made for another call or another store' do
      ask_shopper_erasure(signed_as: ['POST', provisioning_path(ProvisioningRequests::STORE, '/shoppers/data-request')])
      expect_unauthorized
      ask_data_request(signed_as: ['POST', provisioning_path('other-store.myshopify.com', '/shoppers/data-request')])
      expect_unauthorized
      ask_shopper_counts(signed_as: ['GET', provisioning_path(ProvisioningRequests::STORE, '/shoppers/erasure')])
      expect_unauthorized
      nothing_made
    end

    it 'refuses a stale or a future timestamp' do
      calls.each do |name|
        call(name, timestamp: 301.seconds.ago.to_i)
        expect_unauthorized
        call(name, timestamp: 301.seconds.from_now.to_i)
        expect_unauthorized
      end
      nothing_made
    end

    it 'refuses an address one segment deeper or of another kind' do
      ['/shoppers/erasure/again', '/shoppers', '/shoppers/other'].each do |suffix|
        provisioning_call(:post, ProvisioningRequests::STORE, body: shopper_body(ShopperRequests::SHOPPER, nil), suffix: suffix)
        expect(response.status).to be_in([401, 404])
        expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
      end
      nothing_made
    end

    it 'refuses a request id used for another body, and answers a repetition from the stored answer' do
      request_id = SecureRandom.uuid
      ask_shopper_erasure(request_id: request_id)
      expect(response.parsed_body['state']).to eq('waiting')
      first = response.parsed_body

      ask_shopper_erasure(request_id: request_id, shopper: { email: 'kim@example.com' })
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'request_id_reused')

      expect { ask_shopper_erasure(request_id: request_id) }.not_to change(Inclamo::ErasureRequest, :count)
      expect(response.parsed_body).to eq(first)
      expect(Inclamo::ErasureRequest.count).to eq(1)
      expect(Redis::Alfred.get(Inclamo::Provisioning::RequestStore.key(request_id))).not_to include('pat@example.com')
    end

    it 'records every refused attempt' do
      ask_shopper_erasure(secret: 'another-secret-0123456789abcdef-0123456789abcdef')
      ask_data_request(body: { contract: 1, shopper: {} })

      expect(events_of.last(2)).to eq(%w[refused refused])
      expect(Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values }.join(' ')).not_to include('pat@example.com')
    end
  end
end
