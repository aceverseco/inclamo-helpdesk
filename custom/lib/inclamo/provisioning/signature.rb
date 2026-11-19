# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The signature of a provisioning request:
    #   sha256=<hex HMAC-SHA256(secret, "<timestamp>.<request id>.<METHOD>.<path>.<raw body>")>
    # The request id is signed so that a captured request cannot be sent again
    # under another id; the method and the path, so that a captured status
    # request cannot be replayed as a removal. The request id is signed as the
    # header carries it.
    module Signature
      PREFIX = 'sha256='
      WINDOW = 300

      module_function

      def sign(secret, timestamp:, request_id:, method:, path:, body:)
        text = "#{timestamp}.#{request_id}.#{method.to_s.upcase}.#{path}.#{body}"
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
