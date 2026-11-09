# frozen_string_literal: true

module Inclamo
  module Ai
    # Disconnects an account from the AI service (design D4): every pending
    # conversation of the connected inboxes goes to the team, the bot is
    # detached and removed with its token at once, the connection is marked
    # disconnected, and the AI service is told, best effort. The Phone inbox,
    # its conversations and the labels stay.
    class Disconnect
      def self.call(...)
        new(...).call
      end

      def initialize(account:, client: ServiceClient.new)
        @account = account
        @client = client
      end

      def call
        Ai.with_account_lock(@account) do
          record = Inclamo::AiConnection.active_for(@account.id)
          raise Error::NotConnected, 'the account is not connected' unless record

          bot = record.agent_bot
          token = bot&.access_token&.token
          hand_over(record)
          Ai.remove_bot(bot)
          record.update!(state: 'disconnected', disconnected_at: Time.current, removal_error: nil)
          tell_service(record, token)
          record
        end
      end

      private

      # Chatwoot's own handover: the AI assignee is cleared and the
      # conversation opens, as when the agent hands over itself.
      def hand_over(record)
        Conversation.where(account_id: @account.id, inbox_id: record.connected_inbox_ids, status: :pending).find_each(&:bot_handoff!)
      end

      def tell_service(record, token)
        return record.update!(removal_error: 'no_connection_id') if record.connection_id.blank? || token.blank?

        @client.remove(service_url: record.service_url, connection_id: record.connection_id, token: token)
      rescue Error::NotAnswered
        record.update!(removal_error: 'not_answered')
      end
    end
  end
end
