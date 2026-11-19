# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The store's storefront chat (capability app-storefront-chat, contract in
    # docs/app-storefront-chat.md): one website inbox per provisioned account,
    # which the store app shows on the storefront through its own theme
    # extension. Which inbox it is is kept on the store's row, so the team may
    # rename it and keep website inboxes of their own.
    #
    # The inbox is an ordinary website inbox with Chatwoot's defaults. Nothing
    # of it is changed after it is made, and no agent bot is attached here: an
    # inbox made while the account's AI agent is connected is then given to the
    # agent by Inclamo::Ai::ChangeInboxes (capability agent-inbox-selection).
    class StorefrontChat
      Result = Struct.new(:row, :inbox, :outcome, keyword_init: true)

      # The request cannot be served for this store; `code` is the contract's.
      class Refused < StandardError
        STATUSES = { 'no_account' => :not_found, 'no_storefront_chat' => :not_found, 'account_suspended' => :conflict }.freeze

        attr_reader :code

        def initialize(code)
          @code = code
          super
        end

        def status
          STATUSES.fetch(code)
        end
      end

      # Makes the storefront inbox of an account that has none. The caller
      # holds the store's row (its lock, or the transaction that inserted it).
      # `website_url` is the storefront's address; the store's own Shopify
      # address when none is given.
      def self.create!(row, account, website_url = nil)
        channel = Channel::WebWidget.create!(account_id: account.id, website_url: website_url.presence || "https://#{row.shop_domain}")
        inbox = account.inboxes.create!(name: account.name, channel: channel)
        # People conversations can be assigned to; whom else to add is the team's choice.
        inbox.add_members(account.administrators.pluck(:id))
        row.update!(storefront_inbox: inbox)
        inbox
      end

      # What the store has now, for the status call: the row and its inbox.
      def self.find(shop_domain)
        row = Provisioning.store_domain(shop_domain) && ProvisionedAccount.for_store(shop_domain)
        raise Refused, 'no_account' unless row&.account
        raise Refused, 'no_storefront_chat' unless row.storefront_inbox

        Result.new(row: row, inbox: row.storefront_inbox)
      end

      def initialize(shop_domain, website_url: nil)
        @shop_domain = shop_domain
        @website_url = website_url
      end

      # Finds the store's storefront inbox or makes it. The row is locked, so
      # two requests arriving together end with one inbox. Safe to repeat.
      def call
        row = Provisioning.store_domain(@shop_domain) && ProvisionedAccount.for_store(@shop_domain)
        raise Refused, 'no_account' unless row&.account

        result = row.with_lock do
          account = row.account
          raise Refused, 'account_suspended' if row.suspended? || account.suspended?

          inbox = row.storefront_inbox
          next Result.new(row: row, inbox: inbox, outcome: 'existed') if inbox

          Result.new(row: row, inbox: self.class.create!(row, account, @website_url), outcome: 'created')
        end
        # Once the new inbox is committed, so that nothing the agent's side
        # does can undo it.
        Ai::ChangeInboxes.add_storefront_inbox(result.row.account, result.inbox) if result.outcome == 'created'
        result
      end
    end
  end
end
