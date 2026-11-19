# frozen_string_literal: true

module Inclamo
  module Provisioning
    # Where the agent starts when the store app connects it
    # (docs/app-agent-connection.md §3.4): the account's storefront inbox, the
    # one app-storefront-chat keeps on the store's row, or none. It is none
    # when that column is not there (an installation without the storefront
    # chat), when the row names no inbox, when the inbox is gone, is not a
    # website inbox of this account, or already has a bot or Dialogflow.
    # The app's request names no inbox; nothing it sends reaches this choice.
    module AgentInbox
      COLUMN = 'storefront_inbox_id'

      module_function

      # The inbox, or nil.
      def for(account)
        return unless column?

        id = ProvisionedAccount.where(account_id: account.id).pick(COLUMN)
        inbox = id && account.inboxes.find_by(id: id, channel_type: 'Channel::WebWidget')
        inbox if inbox && inbox.conflicting_bot_provider(:inclamo).nil?
      end

      # Asked of the database each time, so the answer does not depend on the
      # order the two changes' migrations ran in.
      def column?
        ProvisionedAccount.connection.column_exists?(ProvisionedAccount.table_name, COLUMN)
      end
    end
  end
end
