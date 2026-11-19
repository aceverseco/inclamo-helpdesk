# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The body of "the store has an account", read and checked before anything
    # is created. A body that does not read raises Invalid with the contract's
    # error code; the message is English text for a developer's log.
    class Payload
      class Invalid < StandardError
        attr_reader :code

        def initialize(code, message)
          @code = code
          super(message)
        end
      end

      MAX_TEXT = 255

      attr_reader :shop_domain, :shop_name, :locale, :timezone, :admin_email, :admin_name

      # `address_domain` is the {shop_domain} of the request's address.
      def initialize(raw_body, address_domain)
        body = parse(raw_body)
        shop = hash(body['shop'])
        admin = hash(body['admin'])
        invalid!('contract_unsupported', "contract must be #{CONTRACT}") unless body['contract'] == CONTRACT

        @shop_domain = read_domain(shop['domain'], address_domain)
        @shop_name = text(shop['name']) || invalid!('shop_name_missing', 'shop.name is absent or empty')
        @admin_email = read_email(admin['email'])
        @admin_name = text(admin['name']) || invalid!('admin_name_missing', 'admin.name is absent or empty')
        invalid!('admin_email_unverified', 'admin.email_verified must be true') unless admin['email_verified'] == true
        @locale = text(shop['locale'])
        @timezone = text(shop['timezone'])
      end

      private

      # A body that is not a JSON object states no contract version at all.
      def parse(raw_body)
        body = JSON.parse(raw_body.to_s)
        body.is_a?(Hash) ? body : invalid!('contract_unsupported', 'the body is not a JSON object')
      rescue JSON::ParserError
        invalid!('contract_unsupported', 'the body is not a JSON object')
      end

      def read_domain(value, address_domain)
        address = Provisioning.store_domain(address_domain)
        invalid!('shop_domain_invalid', 'the address is not a myshopify.com domain') unless address
        invalid!('shop_domain_invalid', 'shop.domain differs from the address') unless value.is_a?(String) && value.strip.downcase == address

        address
      end

      def read_email(value)
        email = value.is_a?(String) ? value.strip.downcase : ''
        return email if email.length <= MAX_TEXT && Devise.email_regexp.match?(email)

        invalid!('admin_email_missing', 'admin.email is absent or does not read as an email')
      end

      def text(value)
        value.strip.first(MAX_TEXT).presence if value.is_a?(String)
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def invalid!(code, message)
        raise Invalid.new(code, message)
      end
    end
  end
end
