# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/entry_requests')

# The limits of a staff member's entry (docs/app-admin-entry.md §4): the
# app's requests per person in a store and per store, and the openings of
# one-time addresses per network address. Chatwoot's limits on its sign-in
# form are untouched.
RSpec.describe 'App admin entry: limits', type: :request do
  include_context 'with app admin entry'

  # As in the provisioning limits' spec: Rack::Attack on, counting in memory,
  # for an address outside the allow-list.
  let(:outside) { { 'REMOTE_ADDR' => '203.0.113.9' } }
  let!(:account) { store_account }

  around do |example|
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = store
    Rack::Attack.enabled = enabled
  end

  before do
    member(account, 'alex@example.test', role: :administrator)
    member(account, 'sam@example.test', role: :agent)
  end

  def expect_limited
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'rate_limited')
    expect(response.headers['Retry-After'].to_i).to be_between(1, 3600)
    expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
    expect(response.body).not_to include('entry_url')
  end

  def counter_keys
    Rack::Attack.cache.store.instance_variable_get(:@data).keys
  end

  it 'has the defaults of the contract, which the operator may change' do
    limits = Inclamo::Provisioning::EntryLimits
    with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_PERSON_LIMIT: nil, INCLAMO_APP_PROVISIONING_ENTRY_STORE_LIMIT: 'many',
                      INCLAMO_APP_PROVISIONING_ENTRY_OPEN_LIMIT: '0' do
      expect(%i[person store opening].map { |name| limits.limit(name) }).to eq([20, 300, 30])
    end
    with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_PERSON_LIMIT: '2', INCLAMO_APP_PROVISIONING_ENTRY_STORE_LIMIT: '7',
                      INCLAMO_APP_PROVISIONING_ENTRY_OPEN_LIMIT: '9' do
      expect(%i[person store opening].map { |name| limits.limit(name) }).to eq([2, 7, 9])
    end
    expect(Rack::Attack.throttles.keys).to include(limits::PERSON, limits::STORE, limits::OPENING)
    expect([limits::PERSON, limits::STORE].map { |name| Rack::Attack.throttles.fetch(name).period }).to eq([3600, 3600])
    expect(Rack::Attack.throttles.fetch(limits::OPENING).period).to eq(300)
  end

  it 'answers requests over one person\'s limit with the time to try again and no address, and no counter names the email' do
    with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_PERSON_LIMIT: '2' do
      2.times do
        ask_entry(headers: outside)
        expect(response).to have_http_status(:ok)
      end
      keys_before = entry_keys

      ask_entry(headers: outside)
      expect_limited
      ask_entry(headers: outside, staff: { email: ' ALEX@example.test' })
      expect_limited
      expect(entry_keys).to eq(keys_before)
      expect(outcomes.last(2)).to eq(%w[entry_limited entry_limited])

      # Another person of the same store, and the same person in another store.
      ask_entry(headers: outside, staff: { email: 'sam@example.test' })
      expect(response).to have_http_status(:ok)
      other = store_account('other-store.myshopify.com')
      AccountUser.create!(account: other, user: User.from_email('alex@example.test'), role: :agent)
      ask_entry('other-store.myshopify.com', headers: outside)
      expect(response).to have_http_status(:ok)
    end

    expect(counter_keys).to include(a_string_matching(%r{inclamo/provisioning/entry/person:example-store\.myshopify\.com:\h{64}\z}))
    redis_keys = []
    Redis::Alfred.scan_each { |key| redis_keys << key }
    redis_values = redis_keys.filter_map { |key| Redis::Alfred.get(key) rescue nil } # rubocop:disable Style/RescueModifier
    [counter_keys.join(' '), redis_keys.join(' '), redis_values.join(' ')].each do |text|
      expect(text).not_to match(/(?:alex|sam)(?:@|%40)example\.test/i)
    end
  end

  it 'answers requests over one store\'s limit, whoever they name' do
    with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_STORE_LIMIT: '3' do
      ask_entry(headers: outside)
      ask_entry(headers: outside, staff: { email: 'sam@example.test' })
      ask_entry(headers: outside, staff: { email: 'nobody@example.test' })
      expect(response).to have_http_status(:forbidden)

      ask_entry(headers: outside, staff: { email: 'sam@example.test' })
      expect_limited
      expect(entry_keys.size).to eq(2)

      ask_entry('other-store.myshopify.com', headers: outside)
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'counts a request refused for its body, and not one that is not the app\'s or that reuses its id' do
    with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_PERSON_LIMIT: '2' do
      3.times do
        ask_entry(headers: outside, secret: 'another-secret-0123456789abcdef-0123456789abcdef')
        expect(response).to have_http_status(:unauthorized)
      end
      request_id = SecureRandom.uuid
      timestamp = Time.now.to_i
      ask_entry(headers: outside, request_id: request_id, timestamp: timestamp)
      3.times do
        ask_entry(headers: outside, request_id: request_id, timestamp: timestamp)
        expect(response).to have_http_status(:conflict)
      end
      ask_entry(headers: outside, staff: { email_verified: false })
      expect(response).to have_http_status(:unprocessable_entity)

      ask_entry(headers: outside)
      expect_limited
    end
  end

  it 'leaves the other provisioning calls\' counts apart' do
    with_modified_env INCLAMO_APP_PROVISIONING_STORE_LIMIT: '1', INCLAMO_APP_PROVISIONING_GET_LIMIT: '1' do
      3.times do
        ask_entry(headers: outside)
        expect(response).to have_http_status(:ok)
      end
      ask_status(headers: outside)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'opening the one-time address' do
    let(:browser) { outside.merge('HTTP_USER_AGENT' => EntryRequests::BROWSER) }

    def given_url
      ask_entry
      entry_url
    end

    it 'lets six openings from one address in five minutes sign in, more than Chatwoot\'s sign-in form allows' do
      6.times do
        open_entry(given_url, headers: browser)
        expect(response).to have_http_status(:found)
        expect(response.headers['Location']).to end_with("/app/accounts/#{account.id}/dashboard")
        expect(dashboard_session).to be_present
      end
    end

    it 'shows the login page to the opening over the limit, signs nobody in, and leaves the address usable' do
      with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_OPEN_LIMIT: '30' do
        30.times do
          get "/inclamo/entry/#{SecureRandom.urlsafe_base64(32)}", headers: browser
          expect(response.headers['Location']).to end_with('/app/login')
        end
        url = given_url

        open_entry(url, headers: browser)

        expect(response).to have_http_status(:found)
        expect(response.headers['Location']).to end_with('/app/login')
        expect(response.headers['Referrer-Policy']).to eq('no-referrer')
        expect(dashboard_session).to be_nil
        expect(entry_keys.size).to eq(1)

        open_entry(url, headers: browser.merge('REMOTE_ADDR' => '203.0.113.10'))
        expect(dashboard_session).to be_present
      end
    end

    it 'leaves Chatwoot\'s limit on password sign-ins from one address as it is' do
      6.times do |index|
        post '/auth/sign_in', params: { email: 'alex@example.test', password: "wrong-#{index}" }, headers: outside, as: :json
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(Rack::Attack.throttles.keys).to include('login/ip')
    end
  end
end
