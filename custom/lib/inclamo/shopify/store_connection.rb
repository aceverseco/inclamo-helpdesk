# frozen_string_literal: true

module Inclamo
  module Shopify
    # The only way the rest of the overlay talks to an account's store. Hands
    # out a valid token (renewing a 24-hour one before it expires, or asking
    # the store app for a new key to a store the app provisioned), marks the
    # connection broken when the store refuses it, and does not call the store
    # again until an administrator has checked or renewed the connection.
    #
    # A connection through the store app (`app_key`, see AppKey) is not broken
    # by an app that does not answer: its key is used while it works, and once
    # it has ended Error::StoreDataUnavailable says the store's data is not
    # available for now. After an attempt the app is not asked again on its
    # own for a pause (AppKey.pause_seconds), however many requests need the
    # store meanwhile. The app's refusals that say why (the store does not
    # have it, the account is not its) do break the connection, with the reason.
    class StoreConnection
      RENEW_BEFORE = 5.minutes
      # A token this close to its expiry is not handed out any more.
      USABLE_FOR = 1.minute
      # Seconds one renewal may hold its lock: longer than a token exchange or
      # a request to the store app takes.
      RENEWAL_LOCK = 30
      RENEWAL_WAIT = 0.25

      attr_reader :record

      # `time_limit` (seconds) bounds a whole query, a token renewal included;
      # without it every request has its own default limit.
      def initialize(record, time_limit: nil)
        @record = record
        @time_limit = time_limit
      end

      def query(document_name, variables = {})
        raise Error::ConnectionBroken, 'the store connection needs attention' if record.broken?

        @deadline = @time_limit && (now + @time_limit)
        renewed = false
        begin
          renew!(force: true) if renewed
          Client.new(domain: record.shop_domain, access_token: access_token, **remaining).query(document_name, variables)
        rescue Error::Unauthorized
          # A refused request was not executed, so one retry with a fresh token
          # is safe. A refused renewal is tried once more the same way: only a
          # second refusal breaks the connection.
          if record.renewable? && !renewed
            renewed = true
            retry
          end
          broken!
          raise
        rescue Error::QueryError => e
          # The store refuses the key a scope: the app's scopes at the store
          # have changed, and its next key says which it holds now.
          ask_again_for_scopes if record.app_key? && e.access_denied?
          raise
        ensure
          @deadline = nil
        end
      end

      def access_token
        renew! if record.renewable? && !token_fresh?
        raise Error::StoreDataUnavailable if record.app_key? && !token_usable?

        record.access_token
      end

      # Verifies the stored credentials again and refreshes what we know of
      # the store; through the store app, with a new key.
      def recheck!
        return recheck_app_key! if record.app_key?

        result = Verifier.call(**credentials)
        record.update!(
          shop_name: result.shop_name, shop_currency: result.shop_currency, scopes: result.scopes,
          customer_data_mode: result.customer_data_mode, access_token: result.access_token,
          token_expires_at: result.token_expires_at, api_version: API_VERSION,
          status: 'working', broken_reason: nil, last_checked_at: Time.current
        )
        record
      rescue Error::Unauthorized
        broken!
        raise
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # What is left of the time limit of the query in progress, if it has one.
      def remaining
        @deadline ? { time_limit: @deadline - now } : {}
      end

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
      # no database transaction stays open while the store or the app is
      # asked. A process that finds a renewal under way keeps using the
      # current token while it still works, and otherwise waits for the new
      # one. `force` renews a token the store has just refused, unless another
      # process has replaced it.
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

          record.app_key? ? renew_app_key!(refused) : renew_with_credentials!
        ensure
          ::Redis::Alfred.delete_if_equals(key, owner)
        end
      end

      def renew_with_credentials!
        exchange = TokenExchange.call(domain: record.shop_domain, client_id: record.client_id, client_secret: record.client_secret, **remaining)
        record.update!(access_token: exchange.access_token, token_expires_at: exchange.expires_at)
      end

      # A new key from the store app. Within a pause after the last attempt
      # the app is asked only for a key the store has just refused. When the
      # app gives none, a key that still works is used; one the store refused
      # is not kept.
      def renew_app_key!(refused)
        raise Error::StoreDataUnavailable if refused.nil? && paused?

        row = provisioned_row
        raise Error::StoreDataUnavailable.new('the store app cannot be asked for this store', code: 'not_available') unless row

        pause!
        keep!(AppKey.call(row: row, account_id: record.account_id, **remaining))
      rescue Error::StoreDataUnavailable => e
        pause!(e.retry_after) if e.retry_after
        forget!(refused) if refused
        raise if refused || !token_usable?
      rescue Error::AppKeyRefused => e
        broken!(e.reason)
        raise
      end

      # The key, its end and its scopes. A key that cannot read the store
      # leaves the connection broken: an administrator learns which scope is
      # missing on "check again".
      def keep!(grant)
        raise Error::AppKeyRefused, 'missing_read_scope' if (ShopifyConnection::READ_SCOPES - grant.scopes).any?
        # Suspended while the app was asked: the key is not kept.
        raise Error::StoreDataUnavailable.new('the account was suspended', code: 'suspended') unless provisioned_row

        record.update!(access_token: grant.access_token, token_expires_at: grant.expires_at, scopes: grant.scopes, renewed_at: Time.current)
      end

      # The store refused a scope to the key: a key with the scopes the app
      # holds now is asked for, unless the app was asked within the pause.
      def ask_again_for_scopes
        row = provisioned_row
        return unless row && ::Redis::Alfred.set(pause_key, '1', nx: true, ex: AppKey.pause_seconds)

        keep!(AppKey.call(row: row, account_id: record.account_id, **remaining))
      rescue Error::AppKeyRefused => e
        broken!(e.reason)
      rescue Error::StoreDataUnavailable
        nil
      end

      # A new key, checked against the store as when the connection was made;
      # also how a broken connection through the app works again.
      def recheck_app_key!
        row = provisioned_row
        raise Error::NotThroughApp, 'this installation cannot ask the store app for a key' unless row

        grant = AppKey.call(row: row, account_id: record.account_id)
        pause!
        result = Verifier.call(domain: record.shop_domain, access_token: grant.access_token, granted_scopes: grant.scopes)
        record.update!(AppConnection.attributes(result, grant))
        record
      rescue Error::AppKeyRefused => e
        broken!(e.reason)
        raise
      rescue Error::Unauthorized
        broken!
        raise
      end

      # The store app's row of an active account it provisioned, when this
      # installation can ask the app for its keys.
      def provisioned_row
        row = Inclamo::ProvisionedAccount.find_by(account_id: record.account_id)
        row if row&.active? && AppKey.available?(row)
      end

      def pause_key
        "inclamo:shopify:#{record.id}:app_key_pause"
      end

      def paused?
        ::Redis::Alfred.exists?(pause_key)
      end

      def pause!(retry_after = nil)
        ::Redis::Alfred.set(pause_key, '1', ex: AppKey.pause_seconds(retry_after))
      end

      # A key the store refused is not used again.
      def forget!(refused)
        return unless record.access_token == refused

        record.update_columns(access_token: nil, token_expires_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      # Whether the token in the record is one this process may use instead of renewing.
      def renewed?(refused)
        refused ? record.access_token != refused && token_usable? : token_fresh?
      end

      def broken!(reason = nil)
        record.update_columns(status: 'broken', broken_reason: reason, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
