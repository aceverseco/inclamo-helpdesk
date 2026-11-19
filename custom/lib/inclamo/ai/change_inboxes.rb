# frozen_string_literal: true

module Inclamo
  module Ai
    # Changes the inboxes the AI agent answers in, without disconnecting
    # (capability agent-inbox-selection; docs/ai-connector.md §1.4). Under the
    # lock connecting and disconnecting take, in this order:
    #   1. check the wanted list by the rule of connecting (InboxChoice), an
    #      empty list allowed and the agent's own inboxes not "another bot";
    #      the list the agent already has returns at once and asks nobody;
    #   2. tell the AI service the whole wanted list; when it refuses, has no
    #      such call or does not answer, this raises and nothing has changed;
    #   3. hand every Pending conversation of the removed inboxes to the team
    #      with Chatwoot's own handover, while the bot is still attached;
    #   4. in one transaction: detach the bot from the removed inboxes, attach
    #      it to the added ones, write the list and clear the last error.
    # When 3 or 4 fails after the AI service accepted, the inboxes stay the
    # earlier ones, the AI service is asked once, best effort, to take the
    # earlier list back, and the connection keeps why the change was not
    # completed (`inbox_change_error`) until a later change succeeds.
    #
    # The agent's bot, its token, the Phone inbox and the labels are not
    # touched. `user` is the administrator who saved the page, or nil for the
    # change the helpdesk makes by itself (a storefront chat inbox made again).
    # `inbox_ids` is the wanted list, or a callable given the current list and
    # answering the wanted one, read under the lock.
    class ChangeInboxes
      def self.call(...)
        new(...).call
      end

      # A storefront chat inbox made while the agent is connected gets the
      # agent (capability app-storefront-chat calls this once the inbox is
      # committed). The new inbox is added to the inboxes the agent has; when
      # that does not happen, the inbox stays with the team and the "AI agent"
      # page says so. Never raises: making the inbox has succeeded either way.
      def self.add_storefront_inbox(account, inbox, client: ServiceClient.new)
        return unless Inclamo::AiConnection.active_for(account.id)

        call(account: account, user: nil, inbox_ids: ->(current) { current + [inbox.id] }, client: client)
      rescue Error::NotConnected, Error::NotApplied
        # Disconnected meanwhile; or recorded by the change itself.
        nil
      rescue StandardError => e
        Rails.logger.warn("[inclamo] the AI agent of account #{account.id} could not be given the storefront inbox #{inbox.id}: #{e.class}")
        Inclamo::AiConnection.active.where(account_id: account.id).update_all(inbox_change_error: 'storefront_not_added', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        nil
      end

      def initialize(account:, user:, inbox_ids:, client: ServiceClient.new)
        @account = account
        @user = user
        @inbox_ids = inbox_ids
        @client = client
      end

      def call
        Ai.with_account_lock(@account) do
          record = Inclamo::AiConnection.active_for(@account.id)
          raise Error::NotConnected, 'the account is not connected' unless record&.agent_bot

          change(record, record.agent_bot)
        end
      end

      private

      def change(record, bot)
        current = record.answering_inbox_ids
        chosen = @inbox_ids.respond_to?(:call) ? @inbox_ids.call(current) : @inbox_ids
        wanted = InboxChoice.inboxes!(@account, chosen, phone_inbox_id: record.phone_inbox_id, allow_empty: true, own_bot_id: bot.id)
        return record if wanted.map(&:id).sort == current.sort

        tell(record, bot, wanted.map(&:id))
        apply(record, bot, current, wanted)
        record
      end

      def tell(record, bot, inbox_ids, time_limit: TIME_LIMIT)
        @client.change_inboxes(service_url: record.service_url, connection_id: record.connection_id, token: bot.access_token.token,
                               inbox_ids: inbox_ids, time_limit: time_limit)
      end

      def apply(record, bot, current, wanted)
        removed = current - wanted.map(&:id)
        added = wanted.reject { |inbox| current.include?(inbox.id) }
        hand_over(removed)
        ActiveRecord::Base.transaction do
          AgentBotInbox.where(agent_bot_id: bot.id, inbox_id: removed).destroy_all
          added.each { |inbox| attach(bot, inbox) }
          record.update!(inbox_ids: wanted.map(&:id), inbox_change_error: nil)
        end
        Rails.logger.info("[inclamo] the AI agent's inboxes of account #{@account.id} changed from #{current} to #{wanted.map(&:id)} by #{changed_by}")
      rescue StandardError => e
        take_back(record, bot, current, e)
        raise Error::NotApplied, 'the change of the inboxes was not applied'
      end

      # Chatwoot's own handover, as on a disconnection: the AI assignee is
      # cleared and the conversation opens for the team.
      def hand_over(inbox_ids)
        return if inbox_ids.empty?

        Conversation.where(account_id: @account.id, inbox_id: inbox_ids, status: :pending).find_each(&:bot_handoff!)
      end

      # Another bot may have been attached since the inboxes were checked. An
      # inbox that already carries the agent's bot keeps that link.
      def attach(bot, inbox)
        own = AgentBotInbox.find_by(inbox_id: inbox.id, agent_bot_id: bot.id)
        return own.update!(status: :active) if own

        raise Error::InboxHasBot, 'the inbox has another bot' if inbox.reload.conflicting_bot_provider(:inclamo).present?

        AgentBotInbox.create!(inbox: inbox, agent_bot: bot)
      end

      # The AI service holds a list the helpdesk did not apply: it is asked
      # once to take the earlier list back, and the page says the change was
      # not completed, and whether the AI service could be asked.
      def take_back(record, bot, earlier, error)
        Rails.logger.warn("[inclamo] the AI agent's inboxes of account #{@account.id} were not changed: #{error.class}")
        told = begin
          tell(record, bot, earlier)
          true
        rescue StandardError
          false
        end
        kept = told ? 'not_applied' : 'not_applied_service_not_told'
        Inclamo::AiConnection.where(id: record.id).update_all(inbox_change_error: kept, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        record.reload
      end

      def changed_by
        @user ? "user #{@user.id}" : 'the helpdesk'
      end
    end
  end
end
