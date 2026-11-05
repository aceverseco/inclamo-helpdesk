# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # The store said no: nothing was changed.
      class Refused < StandardError
        attr_reader :code

        def initialize(code, message = nil)
          super(message || code)
          @code = code
        end
      end

      # One order action. `call` returns :accepted or :running, raises Refused
      # when the store or the order does not allow it, and lets errors of the
      # store connection through. It must be safe to call again with the same
      # record: that is how an attempt whose answer was lost is settled.
      class Base
        def initialize(store:, record:, order:)
          @store = store
          @record = record
          @order = order
        end

        # The parameters as they may be kept in the action record: no personal data.
        def self.recordable(params)
          params.to_h.slice(*self::RECORDED).transform_values { |value| value.is_a?(String) ? value.first(200) : value }
        end

        private

        def params
          @record.params
        end

        def user_errors!(errors)
          errors = Array(errors)
          return if errors.empty?

          raise Refused.new('store_refused', errors.map { |error| error['message'] }.join('; ').first(500))
        end

        def remember!(facts)
          @record.update!(progress: @record.progress.merge(facts.stringify_keys))
        end
      end
    end
  end
end
