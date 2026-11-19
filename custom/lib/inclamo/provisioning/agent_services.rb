# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The AI service addresses the operator allows the store app to name
    # (docs/app-agent-connection.md §3.3). Connecting hands the agent bot's
    # access token and secret to the address, and on the app's door nobody
    # vouches for it the way an administrator pasting a code does: so the
    # helpdesk registers only with an address listed here.
    #
    # INCLAMO_APP_AGENT_SERVICE_URLS is a comma-separated list of HTTPS
    # origins, each with an optional path prefix. Several may be listed;
    # adding one changes nothing for connections made with another. An entry
    # that does not read as such an address is left out, and an empty list
    # allows none. The "AI agent" page's codes are not checked against it.
    module AgentServices
      VARIABLE = 'INCLAMO_APP_AGENT_SERVICE_URLS'
      MAX_URL = 2048

      module_function

      def urls
        ENV.fetch(VARIABLE, '').split(',').filter_map { |entry| normalize(entry) }.uniq
      end

      # `address` as normalize gave it.
      def allowed?(address)
        address.present? && urls.include?(address)
      end

      # The address in one spelling (scheme and host in lower case, the usual
      # port left out, no trailing slash), or nil when it is not an address
      # the helpdesk would register with: HTTPS (HTTP only where Chatwoot may
      # reach private networks, a test stack), with a host, and without a
      # name, a password, a query or a fragment.
      def normalize(value)
        text = value.to_s.strip
        return if text.empty? || text.length > MAX_URL || !Ai.acceptable_url?(text)

        uri = URI.parse(text)
        return if uri.userinfo || uri.query || uri.fragment

        port = ":#{uri.port}" unless uri.port == uri.default_port
        "#{uri.scheme.downcase}://#{uri.host.downcase}#{port}#{uri.path.to_s.chomp('/')}"
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
