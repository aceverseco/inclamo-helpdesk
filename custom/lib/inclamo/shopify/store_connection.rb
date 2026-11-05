# frozen_string_literal: true

module Inclamo
  module Shopify
    # The only way the rest of the overlay talks to an account's store. Hands
    # out a valid token (renewing a 24-hour one before it expires), marks the
    # connection broken when the store refuses it, and does not call the store
    # again until an administrator has checked or renewed the connection.
    class StoreConnection
      RENEW_BEFORE = 5.minutes

      attr_reader :record

      def initialize(record)
        @record = record
      end

      def query(document_name, variables = {})
        raise Error::ConnectionBroken, 'the store connection needs attention' if record.broken?

        renewed = false
        begin
          Client.new(domain: record.shop_domain, access_token: access_token).query(document_name, variables)
        rescue Error::Unauthorized
          # A refused request was not executed, so one retry with a fresh token is safe.
          if record.client_credentials? && !renewed
            renewed = true
            renew!(force: true)
            retry
          end
          broken!
          raise
        end
      end

      def access_token
        renew! if record.client_credentials? && !token_fresh?
        record.access_token
      end

      # Verifies the stored credentials again and refreshes what we know of the store.
      def recheck!
        result = Verifier.call(**credentials)
        record.update!(
          shop_name: result.shop_name, shop_currency: result.shop_currency, scopes: result.scopes,
          customer_data_mode: result.customer_data_mode, access_token: result.access_token,
          token_expires_at: result.token_expires_at, api_version: API_VERSION,
          status: 'working', last_checked_at: Time.current
        )
        record
      rescue Error::Unauthorized
        broken!
        raise
      end

      private

      def credentials
        base = { domain: record.shop_domain }
        record.client_credentials? ? base.merge(client_id: record.client_id, client_secret: record.client_secret) : base.merge(access_token: record.access_token)
      end

      def token_fresh?
        record.access_token.present? && record.token_expires_at.present? && record.token_expires_at > RENEW_BEFORE.from_now
      end

      def renew!(force: false)
        record.with_lock do
          # Another process may have renewed it while we waited for the lock.
          next if !force && token_fresh?

          exchange = TokenExchange.call(domain: record.shop_domain, client_id: record.client_id, client_secret: record.client_secret)
          record.update!(access_token: exchange.access_token, token_expires_at: exchange.expires_at)
        end
      rescue Error::Unauthorized
        broken!
        raise
      end

      def broken!
        record.update_columns(status: 'broken', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
