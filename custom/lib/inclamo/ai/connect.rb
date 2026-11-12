# frozen_string_literal: true

module Inclamo
  module Ai
    # Connects an account to the AI service with a code it issued, in the order
    # of design D3, so that a refusal leaves nothing behind:
    #   1. read the code (an unreadable one stops here, before any request);
    #   2. create the agent bot, with no address yet: Chatwoot sends nothing to
    #      a bot without one (app/listeners/agent_bot_listener.rb:85);
    #   3. create the "Phone" API inbox, unless ours from an earlier connection exists;
    #   4. register with the AI service;
    #   5. refused or unanswered: remove the bot and a Phone inbox made in 3;
    #   6. accepted: point the bot at the address the AI service gave, turn off
    #      keep_pending_on_bot_failure, create the fixed labels and the
    #      attributes of a call, attach the bot to the chosen inboxes and save
    #      the connection, all in one transaction.
    class Connect
      PHONE_INBOX_NAME = 'Phone'

      def self.call(...)
        new(...).call
      end

      def initialize(account:, user:, code:, inbox_ids:, client: ServiceClient.new)
        @account = account
        @user = user
        @code_text = code
        @inbox_ids = inbox_ids
        @client = client
      end

      def call
        raise Error::EncryptionNotConfigured, 'encryption is not configured' unless Chatwoot.encryption_configured?

        code = ConnectionCode.read(@code_text)
        Ai.with_account_lock(@account) do
          record = Inclamo::AiConnection.find_or_initialize_by(account_id: @account.id)
          raise Error::AlreadyConnected, 'the account is connected' if record.persisted? && record.active?

          connect(record, code, chosen_inboxes(record))
        end
      end

      private

      def connect(record, code, inboxes)
        bot = AgentBot.create!(account: @account, name: I18n.t('inclamo.ai_connection.bot_name'), description: I18n.t('inclamo.ai_connection.bot_description'))
        phone, phone_made = phone_inbox(record)
        registration = register(code, bot, phone, inboxes)
        finish(record, code, registration, bot, phone, inboxes)
      rescue StandardError
        undo(bot, phone_made ? phone : nil) if bot
        raise
      end

      def register(code, bot, phone, inboxes)
        @client.register(code, {
                           contract: CONTRACT,
                           helpdesk_url: ENV.fetch('FRONTEND_URL', ''),
                           account: { id: @account.id, name: @account.name },
                           bot: { id: bot.id, access_token: bot.access_token.token, secret: bot.secret },
                           phone_inbox_id: phone.id,
                           inbox_ids: inboxes.map(&:id)
                         })
      rescue Error::NotAnswered => e
        forget(code.service_url, e.connection_id, bot)
        raise
      end

      def finish(record, code, registration, bot, phone, inboxes)
        ActiveRecord::Base.transaction do
          bot.update!(outgoing_url: registration.webhook_url)
          @account.keep_pending_on_bot_failure = false
          @account.save!
          Labels.ensure_fixed!(@account)
          Calls::Attributes.define!(@account)
          inboxes.each { |inbox| attach(bot, inbox) }
          record.update!(
            service_url: code.service_url, connection_id: registration.connection_id, agent_bot_id: bot.id,
            phone_inbox_id: phone.id, inbox_ids: inboxes.map(&:id), state: 'connected', connected_by: @user,
            connected_at: Time.current, disconnected_at: nil, removal_error: nil,
            last_delivered_at: nil, last_failed_at: nil, last_error: nil, last_reply_at: nil
          )
        end
        record
      rescue StandardError
        # The AI service accepted a connection the helpdesk could not finish.
        forget(code.service_url, registration.connection_id, bot)
        raise
      end

      # Another bot may have been attached since the inboxes were checked.
      def attach(bot, inbox)
        raise Error::InboxHasBot, 'the inbox has another bot' if inbox.reload.conflicting_bot_provider(:inclamo).present?

        AgentBotInbox.create!(inbox: inbox, agent_bot: bot)
      end

      def chosen_inboxes(record)
        ids = Array(@inbox_ids).map(&:to_i).select(&:positive?).uniq
        raise Error::NoInboxes, 'no inbox was chosen' if ids.empty?

        inboxes = @account.inboxes.where(id: ids).to_a
        raise Error::InvalidInbox, 'not an inbox of the account' if inboxes.size != ids.size
        raise Error::InvalidInbox, 'the Phone inbox takes no turns of the agent' if record.phone_inbox_id && ids.include?(record.phone_inbox_id)
        raise Error::InboxHasBot, 'an inbox has another bot' if inboxes.any? { |inbox| inbox.conflicting_bot_provider(:inclamo).present? }

        inboxes.sort_by { |inbox| ids.index(inbox.id) }
      end

      # [inbox, made_now]
      def phone_inbox(record)
        existing = record.phone_inbox_id && @account.inboxes.find_by(id: record.phone_inbox_id, channel_type: 'Channel::Api')
        return [existing, false] if existing

        inbox = ActiveRecord::Base.transaction do
          @account.inboxes.create!(name: PHONE_INBOX_NAME, channel: Channel::Api.create!(account: @account))
        end
        [inbox, true]
      end

      # Best effort: the AI service made a connection that will not be used.
      def forget(service_url, connection_id, bot)
        return if connection_id.blank?

        @client.remove(service_url: service_url, connection_id: connection_id, token: bot.access_token.token)
      rescue StandardError => e
        Rails.logger.warn("[inclamo] the AI service could not be told to forget a connection: #{e.class}")
      end

      def undo(bot, phone)
        Ai.remove_bot(bot)
        phone&.destroy!
      end
    end
  end
end
