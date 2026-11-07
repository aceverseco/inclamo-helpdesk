# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Replaces the shipping address. The address passes through to the store
      # and is not kept: the record only says that it was changed.
      class Address < Base
        RECORDED = [].freeze
        FIELDS = { 'first_name' => :firstName, 'last_name' => :lastName, 'company' => :company, 'address1' => :address1,
                   'address2' => :address2, 'city' => :city, 'province_code' => :provinceCode, 'zip' => :zip,
                   'country_code' => :countryCode, 'phone' => :phone }.freeze
        REQUIRED = %w[address1 city country_code].freeze

        def initialize(address:, **rest)
          super(**rest)
          @address = address.to_h.stringify_keys
        end

        def call
          missing = REQUIRED.select { |field| @address[field].blank? }
          raise Refused.new('address_incomplete', "missing: #{missing.join(', ')}") if missing.any?

          # Every field the form holds is sent, a cleared one as null, so that
          # what the agent cleared is cleared at the store as well.
          input = FIELDS.each_with_object({}) { |(ours, theirs), result| result[theirs] = @address[ours].to_s.strip.presence if @address.key?(ours) }
          answer = @store.query(:order_address_update, { input: { id: @record.order_id, shippingAddress: input } })['orderUpdate']
          user_errors!(answer['userErrors'])
          :accepted
        end
      end
    end
  end
end
