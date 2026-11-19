# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')

# The limits of the requests about one shopper (docs/app-store-erasure.md §8):
# the two `POST`s count with the store's erasure, for the installation and for
# one store, apart from the `PUT`s; the `GET` counts with the installation's
# other status calls. Over a limit: `429` with the time to try again, and
# nothing is made or deleted.
RSpec.describe 'App store erasure: limits of the requests about one shopper', type: :request do
  include_context 'with app provisioning'
  include ShopperRequests

  let(:outside) { { 'REMOTE_ADDR' => '203.0.113.9' } }

  around do |example|
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    with_modified_env(INCLAMO_APP_PROVISIONING_ERASURE_LIMIT: '6', INCLAMO_APP_PROVISIONING_ERASURE_STORE_LIMIT: '3',
                      INCLAMO_APP_PROVISIONING_GET_LIMIT: '3') { example.run }
  ensure
    Rack::Attack.cache.store = store
    Rack::Attack.enabled = enabled
  end

  def expect_limited
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'rate_limited')
    expect(response.headers['Retry-After'].to_i).to be_between(1, 3600)
    expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
  end

  before do
    active_store(headers: outside)
    shopper_contact(provisioned.account)
  end

  it 'answers a request over one store\'s limit with the time to try again, and makes and deletes nothing' do
    ask_erasure(headers: outside)
    ask_data_request(headers: outside, body: { contract: 1, shopper: {} })
    expect(response).to have_http_status(:unprocessable_entity)
    ask_data_request(headers: outside, shopper: { email: 'nobody@example.com' })
    expect(response.parsed_body['state']).to eq('none')

    expect { ask_shopper_erasure(headers: outside) }.to not_change(Inclamo::ErasureRequest, :count).and not_change(Contact, :count)

    expect_limited
    expect(Inclamo::DataRequestInbox.count).to eq(0)
    expect(events_of.last).to eq('limited')
    ask_shopper_erasure('other-store.myshopify.com', headers: outside)
    expect(response).to have_http_status(:ok)
  end

  it 'answers requests over the installation\'s limit, whichever store they name' do
    6.times { |number| ask_shopper_erasure("store-#{number}.myshopify.com", headers: outside) }
    expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none', 'contacts' => 0)

    ask_data_request('store-7.myshopify.com', headers: outside)
    expect_limited
  end

  it 'answers a status call over the installation\'s status limit, counted with the other status calls, and does not count a repetition' do
    ask_status(headers: outside)
    request_id = SecureRandom.uuid
    ask_shopper_counts(headers: outside, request_id: request_id)
    3.times do
      ask_shopper_counts(headers: outside, request_id: request_id)
      expect(response).to have_http_status(:ok)
    end
    ask_shopper_counts(headers: outside)
    expect(response).to have_http_status(:ok)

    ask_shopper_counts(headers: outside)

    expect_limited
    ask_shopper_erasure(headers: outside)
    expect(response.parsed_body['state']).to eq('waiting')
  end
end
