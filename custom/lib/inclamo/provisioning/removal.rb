# frozen_string_literal: true

module Inclamo
  module Provisioning
    # "The app was removed": suspends the store's account. Suspension is
    # Chatwoot's own account status, so its checks refuse the dashboard, the
    # widget and the channels; nothing of the account is deleted, and a user's
    # sessions are left alone since they may belong to other accounts.
    # Returns the state afterwards: 'suspended', or 'none' for a store that has
    # no account. Repeating it changes nothing. The account's AI agent is
    # disconnected as part of it (AgentConnection.suspending), and the key to
    # its store deleted (Shopify::AppConnection.forget_key!).
    class Removal
      def initialize(shop_domain)
        @shop_domain = shop_domain
      end

      def call
        row = Provisioning.store_domain(@shop_domain) && ProvisionedAccount.for_store(@shop_domain)
        return 'none' unless row&.account

        AgentConnection.suspending(row.account) do
          row.with_lock do
            row.account.update!(status: :suspended) unless row.account.suspended?
            row.update!(state: 'suspended') unless row.suspended?
            Inclamo::Shopify::AppConnection.forget_key!(row.account)
          end
        end
        'suspended'
      end
    end
  end
end
