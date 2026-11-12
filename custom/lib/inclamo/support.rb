# frozen_string_literal: true

module Inclamo::Support
  class Invalid < StandardError; end
  class Unauthorized < StandardError; end
  class Conflict < StandardError; end
  class Unavailable < StandardError; end
  class RateLimited < StandardError; end

  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  MAX_FILES = 5
  MAX_BYTES = 10 * 1024 * 1024
  MAX_BODY = 50_000

  def self.central?
    ENV['INCLAMO_SUPPORT_CENTRAL'] == 'true'
  end

  def self.inbox
    raise Unavailable unless central?

    inbox = Inbox.find_by!(id: ENV['INCLAMO_SUPPORT_INBOX_ID'], account_id: ENV['INCLAMO_SUPPORT_ACCOUNT_ID'])
    raise Unavailable unless inbox.channel_type == 'Channel::Api' && !inbox.lock_to_single_conversation?

    inbox
  end

  def self.endpoint
    ENV.fetch('INCLAMO_SUPPORT_ENDPOINT', '').delete_suffix('/')
  end

  def self.base_url
    ENV.fetch('FRONTEND_URL', '').delete_suffix('/')
  end

  def self.valid_url!(value)
    uri = URI.parse(value.to_s)
    secure = uri.scheme == 'https' || (ENV['INCLAMO_SUPPORT_TEST_NETWORK'] == 'true' && uri.scheme == 'http')
    raise Invalid, 'invalid_url' unless secure && uri.host.present? && !uri.userinfo && !uri.query && !uri.fragment

    value
  rescue URI::InvalidURIError
    raise Invalid, 'invalid_url'
  end

  def self.actor(member)
    { 'key' => "user:#{member.user_id}", 'name' => member.user.name.to_s.first(120),
      'email' => member.user.email, 'administrator' => member.administrator? }
  end
end
