# frozen_string_literal: true

module Inclamo
  module Ai
    # The two things a connection code carries, handed over as fields instead
    # of an encoded string: the AI service's address and a one-time pairing
    # token. The store app sends them (docs/app-agent-connection.md); Connect
    # reads them through the same interface as a ConnectionCode, so the
    # registration is the same call whichever door was used. Whether the
    # address may be used at all is decided before one is made.
    Pairing = Data.define(:service_url, :token) do
      def initialize(service_url:, token:)
        super(service_url: service_url.to_s.strip.chomp('/'), token: token.to_s)
      end

      def connections_url
        "#{service_url}/connections"
      end

      # Never the token, in a log line or an error report.
      def inspect
        "#<#{self.class.name} service_url=#{service_url.inspect}>"
      end
      alias_method :to_s, :inspect
    end
  end
end
