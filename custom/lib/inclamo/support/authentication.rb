# frozen_string_literal: true

require 'base64'
require 'digest'
require 'openssl'

module Inclamo::Support::Authentication
  module_function

  def canonical(method, path, timestamp, body)
    [method.upcase, path, timestamp.to_s, Digest::SHA256.hexdigest(body)].join("\n")
  end

  def sign(private_key, method, path, timestamp, body)
    Base64.strict_encode64(OpenSSL::PKey.read(private_key).sign(nil, canonical(method, path, timestamp, body)))
  end

  def verify!(public_key, signature, method, path, timestamp, body)
    raise Inclamo::Support::Unauthorized unless timestamp.to_s.match?(/\A\d{10}\z/) && (Time.now.to_i - timestamp.to_i).abs <= 300

    key = OpenSSL::PKey.read(public_key)
    raise Inclamo::Support::Unauthorized unless key.oid == 'ED25519' && public_key.strip == key.public_to_pem.strip
    raise Inclamo::Support::Unauthorized unless key.verify(nil, Base64.strict_decode64(signature.to_s), canonical(method, path, timestamp, body))
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    raise Inclamo::Support::Unauthorized
  end

  def fingerprint(public_key)
    Digest::SHA256.hexdigest(OpenSSL::PKey.read(public_key).public_to_der)
  end

  def rate!(subject, limit:, seconds: 60)
    bucket = Time.now.to_i / seconds
    key = "#{subject}:#{bucket}"
    record = Inclamo::Support::Throttle.create_or_find_by!(key: key) { |row| row.expires_at = Time.at((bucket + 2) * seconds) }
    record.with_lock do
      raise Inclamo::Support::RateLimited if record.hits >= limit

      record.increment!(:hits)
    end
  end
end
