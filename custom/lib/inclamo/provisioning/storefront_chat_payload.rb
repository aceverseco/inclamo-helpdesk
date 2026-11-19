# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The body of "the store has its storefront inbox"
    # (docs/app-storefront-chat.md §2.2), read and checked before anything is
    # looked up or created. A body that does not read raises Payload::Invalid
    # with the contract's error code.
    class StorefrontChatPayload
      MAX_URL = 2048

      # The origin of the storefront address the app named, or nil when it
      # named none.
      attr_reader :storefront_url

      def initialize(raw_body)
        body = parse(raw_body)
        invalid!('contract_unsupported', "contract must be #{CONTRACT}") unless body['contract'] == CONTRACT

        @storefront_url = origin(body['storefront_url']) unless body['storefront_url'].nil?
      end

      private

      # A body that is not a JSON object states no contract version at all.
      def parse(raw_body)
        body = JSON.parse(raw_body.to_s)
        body.is_a?(Hash) ? body : invalid!('contract_unsupported', 'the body is not a JSON object')
      rescue JSON::ParserError
        invalid!('contract_unsupported', 'the body is not a JSON object')
      end

      # Only the origin is kept: the scheme, the host and a port that is not
      # the usual one. A path, a query and a name with a password are dropped.
      def origin(value)
        uri = URI.parse(value.strip) if value.is_a?(String) && value.length <= MAX_URL
        invalid!('storefront_url_invalid', 'storefront_url is not an absolute HTTPS address') unless uri.is_a?(URI::HTTPS) && uri.host.present?

        port = ":#{uri.port}" unless uri.port == uri.default_port
        "https://#{uri.host.downcase}#{port}"
      rescue URI::InvalidURIError
        invalid!('storefront_url_invalid', 'storefront_url is not an absolute HTTPS address')
      end

      def invalid!(code, message)
        raise Payload::Invalid.new(code, message)
      end
    end
  end
end
