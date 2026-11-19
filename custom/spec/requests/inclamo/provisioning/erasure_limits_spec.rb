# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/erasure_requests')

# The erasure requests have counts of their own (docs/app-store-erasure.md §8):
# for the installation and for one store, apart from the `PUT`s, answered
# `429` with the time to try again and erasing or scheduling nothing.
RSpec.describe 'App store erasure: limits', type: :request do
  include_context 'with app provisioning'
  include ErasureRequests

  # As in the provisioning limits' spec: Rack::Attack on, counting in memory,
  # for an address outside the allow-list.
  let(:outside) { { 'REMOTE_ADDR' => '203.0.113.9' } }

  around do |example|
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    with_modified_env(INCLAMO_APP_PROVISIONING_ERASURE_LIMIT: '4', INCLAMO_APP_PROVISIONING_ERASURE_STORE_LIMIT: '2') { example.run }
  ensure
    Rack::Attack.cache.store = store
    Rack::Attack.enabled = enabled
  end

  def store(number)
    "store-#{number}.myshopify.com"
  end

  def expect_limited
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'rate_limited')
    expect(response.headers['Retry-After'].to_i).to be_between(1, 3600)
    expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
  end

  it 'has the defaults of the contract, which the operator may change' do
    with_modified_env INCLAMO_APP_PROVISIONING_ERASURE_LIMIT: nil, INCLAMO_APP_PROVISIONING_ERASURE_STORE_LIMIT: 'many' do
      expect(%i[erasure erasure_store].map { |name| Inclamo::Provisioning.limit(name) }).to eq([60, 20])
    end
    expect(%i[erasure erasure_store].map { |name| Inclamo::Provisioning.limit(name) }).to eq([4, 2])
    expect(Rack::Attack.throttles.keys).to include('inclamo/provisioning/erasure', 'inclamo/provisioning/erasure/store')
  end

  it 'answers a request over one store\'s limit with the time to try again, and schedules nothing for it' do
    suspended_store(headers: outside)
    ask_erasure(headers: outside, body: { contract: 2 })
    expect(response).to have_http_status(:unprocessable_entity)
    ask_erasure(headers: outside, body: { contract: 2 })
    expect(response).to have_http_status(:unprocessable_entity)

    ask_erasure(headers: outside)

    expect_limited
    expect(provisioned).to have_attributes(state: 'suspended', erase_after: nil)
    expect(Inclamo::ErasureRequest.count).to eq(0)
    expect(events_of.last).to eq('limited')

    ask_erasure(store(1), headers: outside)
    expect(response).to have_http_status(:ok)
  end

  it 'answers requests over the installation\'s limit, whichever store they name' do
    4.times do |number|
      ask_erasure(store(number), headers: outside)
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none')
    end

    ask_erasure(store(5), headers: outside)
    expect_limited
  end

  it 'counts apart from the `PUT`s and the status calls, and does not count a repetition from the stored answer' do
    with_modified_env INCLAMO_APP_PROVISIONING_STORE_LIMIT: '1', INCLAMO_APP_PROVISIONING_GET_LIMIT: '1' do
      suspended_store(headers: outside)
      ask_status(headers: outside)

      request_id = SecureRandom.uuid
      ask_erasure(headers: outside, request_id: request_id)
      expect(response.parsed_body['state']).to eq('scheduled')
      3.times do
        ask_erasure(headers: outside, request_id: request_id)
        expect(response.parsed_body['state']).to eq('scheduled')
      end
      ask_erasure(headers: outside)
      expect(response.parsed_body['state']).to eq('scheduled')

      ask_erasure(headers: outside)
      expect_limited
    end
  end

  it 'does not count requests that are not the app\'s' do
    3.times do
      ask_erasure(headers: outside, secret: 'another-secret-0123456789abcdef-0123456789abcdef')
      expect(response).to have_http_status(:unauthorized)
    end

    2.times do
      ask_erasure(headers: outside)
      expect(response).to have_http_status(:ok)
    end
  end
end
