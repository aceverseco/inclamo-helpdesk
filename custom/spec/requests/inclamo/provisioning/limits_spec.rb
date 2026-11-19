# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: limits', type: :request do
  include_context 'with app provisioning'

  # Chatwoot switches Rack::Attack off outside production and trusts the local
  # address; the calls here come from an outside address with it switched on.
  # The counters are kept in memory: the test environment's stand-in for Redis
  # cannot count for Rack::Attack.
  let(:outside) { { 'REMOTE_ADDR' => '203.0.113.9' } }

  around do |example|
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    with_modified_env(INCLAMO_APP_PROVISIONING_PUT_LIMIT: '3', INCLAMO_APP_PROVISIONING_STORE_LIMIT: '2',
                      INCLAMO_APP_PROVISIONING_GET_LIMIT: '2') { example.run }
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
    expect(response.headers['Retry-After']).to match(/\A\d+\z/)
    expect(response.headers['Retry-After'].to_i).to be_between(1, 3600)
  end

  it 'has the defaults of the contract, which the operator may change' do
    with_modified_env INCLAMO_APP_PROVISIONING_PUT_LIMIT: nil, INCLAMO_APP_PROVISIONING_STORE_LIMIT: 'many',
                      INCLAMO_APP_PROVISIONING_GET_LIMIT: '0' do
      expect(%i[put store get].map { |name| Inclamo::Provisioning.limit(name) }).to eq([30, 5, 300])
    end
    expect(%i[put store get].map { |name| Inclamo::Provisioning.limit(name) }).to eq([3, 2, 2])
    expect(Rack::Attack.throttles.keys).to include('inclamo/provisioning/put', 'inclamo/provisioning/put/store', 'inclamo/provisioning/get')
    expect(Rack::Attack.throttles.fetch('inclamo/provisioning/put').period).to eq(3600)
  end

  it 'answers requests over the installation\'s limit with the time to try again, and creates nothing for them' do
    3.times do |number|
      provision(store(number), headers: outside, admin: { email: "person-#{number}@example.test" })
      expect(response).to have_http_status(:created)
    end

    expect do
      provision(store(3), headers: outside, admin: { email: 'person-3@example.test' })
      expect_limited
      provision(store(4), headers: outside, admin: { email: 'person-4@example.test' })
      expect_limited
    end.to not_change(Account, :count).and not_change(User, :count).and not_change(Inclamo::ProvisionedAccount, :count)

    expect(provisioned(store(3))).to be_nil
    expect(User.from_email('person-3@example.test')).to be_nil
    expect(Inclamo::ProvisioningEvent.order(:id).last(2).pluck(:outcome, :shop_domain))
      .to eq([['limited', store(3)], ['limited', store(4)]])
  end

  it 'answers requests over one store\'s limit, and leaves other stores alone' do
    with_modified_env INCLAMO_APP_PROVISIONING_PUT_LIMIT: '30' do
      provision(headers: outside)
      expect(response).to have_http_status(:created)
      remove_app(headers: outside)
      provision(headers: outside)
      expect(response.parsed_body['outcome']).to eq('restored')
      remove_app(headers: outside)

      provision(headers: outside)
      expect_limited
      expect(provisioned).to be_suspended
      expect(provisioned.account).to be_suspended
      expect(Inclamo::ProvisioningEvent.order(:id).last).to have_attributes(outcome: 'limited', shop_domain: ProvisioningRequests::STORE)

      provision('Example-Store.MyShopify.com', body: provisioning_body('example-store.myshopify.com'), headers: outside)
      expect_limited

      provision(store(1), headers: outside)
      expect(response).to have_http_status(:created)
    end
  end

  it 'limits the status call on its own count' do
    2.times do
      ask_status(headers: outside)
      expect(response).to have_http_status(:not_found)
    end
    ask_status(headers: outside)
    expect_limited

    provision(headers: outside)
    expect(response).to have_http_status(:created)
    remove_app(headers: outside)
    expect(response).to have_http_status(:ok)
  end

  it 'does not count requests that are not the app\'s against the limits' do
    6.times do |number|
      provision(store(number), headers: outside, secret: 'another-secret-0123456789abcdef-0123456789abcdef')
      expect(response).to have_http_status(:unauthorized)
      provision(headers: outside, timestamp: 10.minutes.ago.to_i)
      expect(response).to have_http_status(:unauthorized)
      put provisioning_path, params: '{}', headers: outside.merge('CONTENT_TYPE' => 'application/json')
      expect(response).to have_http_status(:unauthorized)
      ask_status(headers: outside, secret: 'another-secret-0123456789abcdef-0123456789abcdef')
      expect(response).to have_http_status(:unauthorized)
    end

    request_id = SecureRandom.uuid
    provision(headers: outside, request_id: request_id)
    expect(response).to have_http_status(:created)
    provision(headers: outside, request_id: request_id, shop: { name: 'Another Body' })
    expect(response).to have_http_status(:unauthorized)

    provision(headers: outside)
    expect(response).to have_http_status(:ok)
    2.times do
      ask_status(headers: outside)
      expect(response).to have_http_status(:ok)
    end
    provision(store(1), headers: outside)
    expect(response).to have_http_status(:created)
  end

  it 'counts nothing on an installation without the secret' do
    with_modified_env INCLAMO_APP_PROVISIONING_SECRET: nil do
      Rails.application.reload_routes!
      5.times do
        provision(headers: outside)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
