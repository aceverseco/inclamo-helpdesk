# frozen_string_literal: true

module Inclamo
  module Shopify
    # The only way the rest of the overlay talks to an account's store. Hands
    # out a valid token (renewing a 24-hour one before it expires), marks the
    # connection broken when the store refuses it, and does not call the store
    # again until an administrator has checked or renewed the connection.
    class StoreConnection
      RENEW_BEFORE = 5.minutes
      # A token this close to its expiry is not handed out any more.
      USABLE_FOR = 1.minute
      # Seconds one renewal may hold its lock: longer than a token exchange takes.
      RENEWAL_LOCK = 30
      RENEWAL_WAIT = 0.25

      attr_reader :record

      def initialize(record)
        @record = record
      end

      def query(document_name, variables = {})
        raise Error::ConnectionBroken, 'the store connection needs attention' if record.broken?

        renewed = false
        begin
          renew!(force: true) if renewed
          Client.new(domain: record.shop_domain, access_token: access_token).query(document_name, variables)
        rescue Error::Unauthorized
          # A refused request was not executed, so one retry with a fresh token
          # is safe. A refused renewal is tried once more the same way: only a
          # second refusal breaks the connection.
          if record.client_credentials? && !renewed
            renewed = true
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

      # A token that still works for a request, although it is due for renewal.
      def token_usable?
        record.access_token.present? && record.token_expires_at.present? && record.token_expires_at > USABLE_FOR.from_now
      end

      # Renews the token, one process at a time. The lock is kept in Redis, so
      # no database transaction stays open while the store is asked. A process
      # that finds a renewal under way keeps using the current token while it
      # still works, and otherwise waits for the new one. `force` renews a token
      # the store has just refused, unless another process has replaced it.
      def renew!(force: false)
        refused = record.access_token if force
        key = "inclamo:shopify:#{record.id}:token_renewal"
        owner = SecureRandom.hex(8)
        until ::Redis::Alfred.set(key, owner, nx: true, ex: RENEWAL_LOCK)
          return if !force && token_usable?

          sleep(RENEWAL_WAIT)
          record.reload
          return if renewed?(refused)
        end
        begin
          record.reload
          return if renewed?(refused)

          exchange = TokenExchange.call(domain: record.shop_domain, client_id: record.client_id, client_secret: record.client_secret)
          record.update!(access_token: exchange.access_token, token_expires_at: exchange.expires_at)
        ensure
          ::Redis::Alfred.delete_if_equals(key, owner)
        end
      end

      # Whether the token in the record is one this process may use instead of renewing.
      def renewed?(refused)
        refused ? record.access_token != refused && token_usable? : token_fresh?
      end

      def broken!
        record.update_columns(status: 'broken', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
