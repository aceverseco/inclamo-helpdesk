# frozen_string_literal: true

require Rails.root.join('custom/spec/support/shopify_stubs')

# The store app's side of docs/app-store-access.md as the helpdesk's specs see
# it: the app's address, its answers to a request for a store key, and an
# account the app provisioned whose store connection is made through it.
module StoreKeyStubs
  SECRET = 'spec-provisioning-secret-0123456789abcdef-0123456789abcdef'
  APP_URL = 'https://app.example.test/helpdesk'
  STORE = 'example-store.myshopify.com'
  KEY = 'key-from-the-app-do-not-leak'
  NEW_KEY = 'new-key-from-the-app-do-not-leak'
  TEN = %w[read_customers read_orders read_products write_orders write_draft_orders write_customers write_order_edits write_discounts
           read_locations read_merchant_managed_fulfillment_orders].freeze

  def store_key_url(domain = STORE, address: APP_URL)
    "#{address}/stores/#{domain}/store-key"
  end

  # The SSRF filter resolves host names; specs have no DNS to ask.
  def resolve_store_app_publicly
    allow(Inclamo::Shopify::AppKey).to receive(:resolver).and_return(->(_host) { [IPAddr.new('93.184.216.34')] })
  end

  def key_answer(token: KEY, domain: STORE, expires_at: 1.hour.from_now, scopes: TEN, **extra)
    { contract: 1, shop_domain: domain, access_token: token, expires_at: expires_at.utc.iso8601, scopes: scopes }.merge(extra)
  end

  # The app's answer to every request for this store's key; several answers
  # are given one after the other.
  def stub_store_key(*answers, domain: STORE, address: APP_URL)
    answers = [key_answer(domain: domain)] if answers.empty?
    responses = answers.map do |answer|
      if answer.is_a?(Hash) && answer.key?(:status)
        body = answer[:body]
        { status: answer[:status], body: body.is_a?(String) ? body : body.to_json, headers: { 'Content-Type' => 'application/json' }.merge(answer[:headers] || {}) }
      else
        { status: 200, body: answer.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
    end
    stub_request(:post, store_key_url(domain, address: address)).to_return(*responses)
  end

  def key_refusal(status, error, headers: {})
    { status: status, body: { error: error, message: 'for a developer' }, headers: headers }
  end

  # An account the store app provisioned for `domain`, active unless told.
  def provisioned_account(domain = STORE, state: 'active', store_access_url: nil)
    account = create(:account)
    Inclamo::ProvisionedAccount.create!(shop_domain: domain, account: account, state: state, store_access_url: store_access_url)
    account
  end

  # Its connection through the app, as AppConnection leaves it.
  def app_key_connection(account, token: KEY, expires_at: 50.minutes.from_now, scopes: TEN.sort, **attributes)
    create(:inclamo_shopify_connection, account: account, auth_kind: 'app_key', client_id: nil, client_secret: nil,
                                        access_token: token, token_expires_at: expires_at, scopes: scopes, renewed_at: 10.minutes.ago, **attributes)
  end

  def key_requests(domain = STORE)
    a_request(:post, store_key_url(domain))
  end

  def clear_app_key_pauses
    Redis::Alfred.with { |redis| redis.scan_each(match: 'inclamo:shopify:*:app_key_pause') { |key| redis.del(key) } }
  end
end

# An installation whose operator set the shared secret and the app's address.
RSpec.shared_context 'with the store app for keys' do
  include ShopifyStubs
  include StoreKeyStubs

  around do |example|
    with_modified_env INCLAMO_APP_PROVISIONING_SECRET: StoreKeyStubs::SECRET, INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS: nil,
                      INCLAMO_APP_URL: StoreKeyStubs::APP_URL, INCLAMO_APP_KEY_PAUSE: nil do
      example.run
    end
  end

  before do
    resolve_store_app_publicly
    clear_app_key_pauses
    Inclamo::Shopify::OrderReader.forget!(0)
  end

  after { clear_app_key_pauses }
end
