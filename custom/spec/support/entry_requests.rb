# frozen_string_literal: true

require Rails.root.join('custom/spec/support/provisioning_requests')

# Plays the store app's entry request (docs/app-admin-entry.md §1) and the
# browser that opens the one-time address, in request specs.
module EntryRequests
  include ProvisioningRequests

  BROWSER = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15'

  # `staff` is laid over a valid staff member; `body` replaces the body.
  def ask_entry(domain = ProvisioningRequests::STORE, staff: {}, body: nil, **)
    body ||= { contract: 1, staff: { email: 'alex@example.test', email_verified: true }.merge(staff) }
    provisioning_call(:post, domain, body: body, suffix: '/entry', **)
  end

  def entry_url
    response.parsed_body.fetch('entry_url')
  end

  # Opens the address as a browser would: the path only, since the test
  # application answers any host.
  def open_entry(url, headers: {})
    get URI.parse(url).path, headers: { 'HTTP_USER_AGENT' => BROWSER }.merge(headers)
    response
  end

  # The dashboard's session as its script reads the cookie (js-cookie decodes
  # every percent sequence), or nil when the answer set none.
  def dashboard_session
    line = Array(response.headers['set-cookie']).join("\n").split("\n").find { |cookie| cookie.start_with?('cw_d_session_info=') }
    return unless line

    raw = line.split(';').first.delete_prefix('cw_d_session_info=')
    JSON.parse(raw.gsub(/(?:%\h{2})+/) { |sequence| [sequence.delete('%')].pack('H*').force_encoding('UTF-8') })
  end

  # A store with its account, as the app's provisioning made it; the account.
  def store_account(domain = ProvisioningRequests::STORE)
    provision(domain, admin: { email: "owner@#{domain.delete_suffix('.myshopify.com')}.test", name: 'Store Owner' })
    provisioned(domain).account
  end

  def member(account, email, role: :agent, **)
    create(:user, email: email, account: account, role: role, **)
  end

  def outcomes(domain = ProvisioningRequests::STORE)
    Inclamo::ProvisioningEvent.where(shop_domain: domain).order(:id).pluck(:outcome)
  end

  def entry_keys
    keys = []
    Redis::Alfred.scan_each(match: 'INCLAMO_ENTRY::*') { |key| keys << key }
    keys
  end

  # What the application logs while the block runs, at the production's
  # level (info: the request log, not the database's).
  def logged
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.level = :info
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end
end

RSpec.shared_context 'with app admin entry' do
  include_context 'with app provisioning'
  include EntryRequests

  after do
    entry_keys.each { |key| Redis::Alfred.delete(key) }
  end
end
