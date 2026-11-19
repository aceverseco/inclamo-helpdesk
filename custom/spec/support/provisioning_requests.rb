# frozen_string_literal: true

# Plays the store app in request specs: signs the three provisioning calls as
# docs/app-provisioning.md describes, with switches for what the app must never
# send (another secret, a stale time, a reused request id).
module ProvisioningRequests
  SECRET = 'spec-provisioning-secret-0123456789abcdef-0123456789abcdef'
  HELPDESK_URL = 'https://helpdesk.example.test'
  STORE = 'example-store.myshopify.com'

  def provisioning_path(domain = STORE, suffix = '')
    "/inclamo/provisioning/stores/#{domain}#{suffix}"
  end

  def provisioning_body(domain = STORE, shop: {}, admin: {}, **top)
    {
      contract: 1,
      shop: { domain: domain, name: 'Example Store', locale: 'fr', timezone: 'America/New_York' }.merge(shop),
      admin: { email: 'alex@example.test', name: 'Alex Example', email_verified: true }.merge(admin)
    }.merge(top)
  end

  # Sends one signed call. `body` is a Hash (sent as JSON), a String (sent as
  # is) or nil. `signed_as` signs for another method and path than the one
  # sent, `signed_id` for another request id.
  def provisioning_call(method, domain = STORE, body: nil, suffix: '', secret: SECRET, timestamp: Time.now.to_i,
                        request_id: SecureRandom.uuid, signed_as: nil, signed_id: nil, headers: {})
    path = provisioning_path(domain, suffix)
    raw = body.is_a?(Hash) ? JSON.generate(body) : body.to_s
    signed_method, signed_path = signed_as || [method.to_s.upcase, path]
    signature = Inclamo::Provisioning::Signature.sign(secret, timestamp: timestamp, request_id: signed_id || request_id,
                                                              method: signed_method, path: signed_path, body: raw)
    public_send(method, path, params: raw, headers: {
      'CONTENT_TYPE' => 'application/json', 'X-Inclamo-Timestamp' => timestamp.to_s,
      'X-Inclamo-Request-Id' => request_id, 'X-Inclamo-Signature' => signature
    }.merge(headers))
    response
  end

  # The account's `PUT`. `shop` and `admin` are laid over a valid body and
  # `store_access_url` is added to it; `body` replaces it.
  def provision(domain = STORE, **options)
    body = options.delete(:body) ||
           provisioning_body(domain, shop: options.delete(:shop) || {}, admin: options.delete(:admin) || {},
                                     **options.extract!(:store_access_url))
    provisioning_call(:put, domain, body: body, **options)
  end

  def remove_app(domain = STORE, **)
    provisioning_call(:post, domain, suffix: '/removal', **)
  end

  def ask_status(domain = STORE, **)
    provisioning_call(:get, domain, **)
  end

  def provisioned(domain = STORE)
    Inclamo::ProvisionedAccount.find_by(shop_domain: domain)
  end
end

RSpec::Matchers.define_negated_matcher :not_change, :change unless RSpec::Matchers.method_defined?(:not_change)
unless RSpec::Matchers.method_defined?(:not_have_enqueued_job)
  RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job
end

# An installation whose operator set the shared secret: the routes are drawn
# for the example and taken away after it.
RSpec.shared_context 'with app provisioning' do
  include ProvisioningRequests

  around do |example|
    with_modified_env INCLAMO_APP_PROVISIONING_SECRET: ProvisioningRequests::SECRET,
                      INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS: nil,
                      FRONTEND_URL: ProvisioningRequests::HELPDESK_URL do
      Rails.application.reload_routes!
      example.run
    end
  ensure
    Rails.application.reload_routes!
  end

  after do
    Redis::Alfred.with do |redis|
      redis.scan_each(match: 'INCLAMO_PROVISIONING_REQUEST::*') { |key| redis.del(key) }
    end
  end
end
