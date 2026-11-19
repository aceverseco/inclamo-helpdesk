# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The signature of a provisioning request:
    #   sha256=<hex HMAC-SHA256(secret, "<timestamp>.<METHOD>.<path>.<raw body>")>
    # The method and the path are signed so a captured status request cannot be
    # replayed as a removal.
    module Signature
      PREFIX = 'sha256='
      WINDOW = 300

      module_function

      def sign(secret, timestamp:, method:, path:, body:)
        text = "#{timestamp}.#{method.to_s.upcase}.#{path}.#{body}"
        PREFIX + OpenSSL::HMAC.hexdigest('SHA256', secret, text)
      end

      # True when the signature was made with one of the secrets. Every secret
      # is compared, in constant time, whichever matches.
      def match?(secrets, given, **parts)
        given = given.to_s
        secrets.map { |secret| ActiveSupport::SecurityUtils.secure_compare(sign(secret, **parts), given) }.any?
      end

      def fresh?(timestamp, now: Time.now.to_i)
        text = timestamp.to_s
        text.match?(/\A\d{1,12}\z/) && (now - text.to_i).abs <= WINDOW
      end
    end
  end
end
