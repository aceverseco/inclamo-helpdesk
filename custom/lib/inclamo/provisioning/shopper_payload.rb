# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The body of the two requests about one shopper
    # (docs/app-store-erasure.md §4.1, §5): the shopper's email and phone as
    # Shopify gave them, and Shopify's order ids. A body that states no
    # contract this installation speaks raises Payload::Invalid with
    # `contract_unsupported`; one without an email and without a phone (with
    # at least one digit) raises it with `shopper_missing`. An order id that
    # is not a string or a number is left out. The messages name no value.
    class ShopperPayload
      MAX_TEXT = 255
      MAX_ORDERS = 1000

      attr_reader :email, :phone, :order_ids

      def initialize(raw_body)
        body = parse(raw_body)
        invalid!('contract_unsupported', "contract must be #{CONTRACT}") unless body['contract'] == CONTRACT

        shopper = body['shopper'].is_a?(Hash) ? body['shopper'] : {}
        @email = text(shopper['email'])
        @phone = text(shopper['phone'])
        @phone = nil unless Erasure::Shoppers.digits(@phone)
        invalid!('shopper_missing', 'shopper.email and shopper.phone are both absent or empty') unless @email || @phone

        @order_ids = Array(body['order_ids']).grep(->(one) { one.is_a?(String) || one.is_a?(Integer) })
                                             .map { |one| one.to_s.strip.first(MAX_TEXT) }.compact_blank.uniq.first(MAX_ORDERS)
      end

      private

      def parse(raw_body)
        body = JSON.parse(raw_body.to_s)
        body.is_a?(Hash) ? body : invalid!('contract_unsupported', 'the body is not a JSON object')
      rescue JSON::ParserError
        invalid!('contract_unsupported', 'the body is not a JSON object')
      end

      def text(value)
        value.is_a?(String) ? value.strip.first(MAX_TEXT).presence : nil
      end

      def invalid!(code, message)
        raise Payload::Invalid.new(code, message)
      end
    end
  end
end
