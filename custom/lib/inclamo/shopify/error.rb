# frozen_string_literal: true

module Inclamo
  module Shopify
    # Everything that can go wrong between us and the store. `outcome_unknown?`
    # says whether the store may have acted on the request anyway.
    class Error < StandardError
      def outcome_unknown?
        false
      end

      # The store did not answer within the time limit.
      class Timeout < Error
        def outcome_unknown?
          true
        end
      end

      # The connection failed or the store answered with a server error.
      class Unavailable < Error
        def outcome_unknown?
          true
        end
      end

      # The store kept throttling until the time limit. Nothing was executed.
      class Throttled < Error; end

      # The token was refused: the connection is broken.
      class Unauthorized < Error; end

      # The shop does not exist, is frozen or is locked.
      class ShopUnavailable < Error; end

      # The store answered with GraphQL errors.
      class QueryError < Error
        attr_reader :codes

        def initialize(message, codes: [])
          super(message)
          @codes = codes
        end

        def access_denied?
          codes.include?('ACCESS_DENIED')
        end
      end
    end
  end
end
