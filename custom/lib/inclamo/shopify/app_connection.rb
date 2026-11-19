# frozen_string_literal: true

module Inclamo
  module Shopify
    # The store connection of an account the store app provisioned
    # (capability app-store-access): made with a key from the app (AppKey)
    # when the account is created or restored, or when an administrator asks
    # for it; the key deleted when the account is suspended. Nobody enters a
    # domain or credentials, and such an account's connection is the app's:
    # it is read and checked again, never replaced or removed by hand.
    module AppConnection
      module_function

      # The store app's row of the account, if the app provisioned it.
      def row_of(account_id)
        Inclamo::ProvisionedAccount.find_by(account_id: account_id)
      end

      def provisioned?(account_id)
        Inclamo::ProvisionedAccount.exists?(account_id: account_id)
      end

      # Whether the account's connection can be made through the app now.
      def available?(row)
        row.present? && row.active? && AppKey.available?(row)
      end

      # Makes the account's connection, or checks an existing one again with a
      # new key. Nothing is saved unless the key opens the account's store and
      # holds the read scopes. A connection made by hand before (an account an
      # operator linked to its store) is left as it is. Raises Shopify errors.
      def connect!(account)
        row = row_of(account.id)
        raise Error::NotThroughApp, 'the account cannot be connected through the store app' unless available?(row)

        existing = ShopifyConnection.find_by(account_id: account.id)
        return existing if existing && !existing.app_key?
        return StoreConnection.new(existing).recheck! if existing

        grant = AppKey.call(row: row, account_id: account.id)
        result = Verifier.call(domain: row.shop_domain, access_token: grant.access_token, granted_scopes: grant.scopes)
        record = ShopifyConnection.create!(attributes(result, grant).merge(account: account))
        ConversationOrder.ensure_definitions!(account)
        CustomerFacts.ensure_definitions!(account)
        record
      rescue ActiveRecord::RecordNotUnique
        # Another request made the connection meanwhile.
        ShopifyConnection.find_by!(account_id: account.id)
      end

      # A connection's attributes from a verified key.
      def attributes(result, grant)
        now = Time.current
        {
          shop_domain: result.shop_domain, shop_name: result.shop_name, shop_currency: result.shop_currency,
          auth_kind: 'app_key', client_id: nil, client_secret: nil,
          access_token: grant.access_token, token_expires_at: grant.expires_at, renewed_at: now,
          scopes: result.scopes, customer_data_mode: result.customer_data_mode,
          api_version: API_VERSION, status: 'working', broken_reason: nil, last_checked_at: now
        }
      end

      # After the store app's request for the store's account: a created or
      # restored account gets its connection in the background, so the app's
      # answer never waits for it or depends on it.
      def after_provisioning(result)
        return unless %w[created restored].include?(result.outcome) && available?(result.row)

        Inclamo::StoreAccessJob.perform_later(result.account.id)
      end

      # On suspension: the key and its scopes are deleted; the connection's
      # record and the record of order actions stay. Earlier answers of the
      # store are made unreachable.
      def forget_key!(account)
        return unless account

        ShopifyConnection.where(account_id: account.id, auth_kind: 'app_key')
                         .update_all(access_token: nil, token_expires_at: nil, scopes: [], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        OrderReader.forget!(account.id)
      end
    end
  end
end
