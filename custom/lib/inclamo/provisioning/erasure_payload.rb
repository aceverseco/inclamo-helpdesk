# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The body of "Shopify asked to erase the store"
    # (docs/app-store-erasure.md §3.1): `{"contract": 1}`. A body that does
    # not state a contract this installation speaks raises Payload::Invalid.
    class ErasurePayload
      def initialize(raw_body)
        body = JSON.parse(raw_body.to_s)
        invalid!('the body is not a JSON object') unless body.is_a?(Hash)
        invalid!("contract must be #{CONTRACT}") unless body['contract'] == CONTRACT
      rescue JSON::ParserError
        invalid!('the body is not a JSON object')
      end

      private

      def invalid!(message)
        raise Payload::Invalid.new('contract_unsupported', message)
      end
    end
  end
end
