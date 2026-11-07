# frozen_string_literal: true

module Inclamo
  module Ai
    # The code the AI service issues to a subscribed merchant (design D2):
    #   aic1.<base64url of {"service_url": "https://…", "token": "…"}>
    # Read before any request is made; a code that does not read raises
    # Error::InvalidCode and nothing is sent anywhere.
    class ConnectionCode
      MAX_LENGTH = 4096

      attr_reader :service_url, :token

      def self.read(text)
        new(text)
      end

      def initialize(text)
        value = text.to_s.strip
        raise Error::InvalidCode, 'not a connection code' unless value.start_with?(CODE_PREFIX) && value.length <= MAX_LENGTH

        fields = decode(value.delete_prefix(CODE_PREFIX))
        @service_url = fields['service_url'].to_s.strip.chomp('/')
        @token = fields['token'].to_s
        raise Error::InvalidCode, 'the code lacks the address or the token' if @service_url.empty? || @token.empty?
        raise Error::InvalidCode, 'the address is not HTTPS' unless Ai.acceptable_url?(@service_url)
      end

      def connections_url
        "#{service_url}/connections"
      end

      private

      def decode(payload)
        raise Error::InvalidCode, 'not a connection code' unless payload.match?(/\A[A-Za-z0-9_-]+={0,2}\z/)

        raw = payload.delete('=')
        fields = JSON.parse(Base64.urlsafe_decode64(raw + ('=' * ((4 - (raw.length % 4)) % 4))))
        raise Error::InvalidCode, 'not a connection code' unless fields.is_a?(Hash)
        raise Error::InvalidCode, 'the code lacks the address or the token' unless fields['service_url'].is_a?(String) && fields['token'].is_a?(String)

        fields
      rescue ArgumentError, JSON::ParserError
        raise Error::InvalidCode, 'not a connection code'
      end
    end
  end
end
