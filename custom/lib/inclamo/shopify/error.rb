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

      # The client ID or secret was refused when asking for a token.
      class CredentialsRefused < Unauthorized; end

      # The credentials are fine, but the app is not installed on this store.
      class AppNotInstalled < Unauthorized; end

      # The connection is marked broken; the store is not called until an
      # administrator has checked or renewed it.
      class ConnectionBroken < Error; end

      # What was entered is not a `<name>.myshopify.com` domain.
      class InvalidDomain < Error; end

      # The app lacks scopes the helpdesk cannot work without.
      class MissingScopes < Error
        attr_reader :scopes

        def initialize(scopes)
          super("missing scopes: #{scopes.join(', ')}")
          @scopes = scopes
        end
      end

      # The store refuses the app its orders: Shopify gives orders, draft orders
      # and customers only to an app for which a distribution method was chosen.
      class OrdersRefused < Error; end

      # The shop does not exist, is frozen or is locked.
      class ShopUnavailable < Error; end

      # The store answered with GraphQL errors.
      class QueryError < Error
        attr_reader :codes, :paths

        # `paths` are the root fields the errors are about, as the store names them.
        def initialize(message, codes: [], paths: [])
          super(message)
          @codes = codes
          @paths = paths
        end

        def access_denied?
          codes.include?('ACCESS_DENIED')
        end
      end
    end
  end
end
