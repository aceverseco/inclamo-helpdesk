# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The store app's door to the AI agent (capability
    # app-agent-auto-connection, contract in docs/app-agent-connection.md):
    # connect a store's account, say how its connection is doing, disconnect
    # it, and disconnect it when the account is suspended.
    #
    # Connecting is Inclamo::Ai::Connect, the service the "AI agent" page uses,
    # given the pairing the app sent instead of a code, no person, and the
    # helpdesk's own choice of inboxes: the storefront inbox or none
    # (AgentInbox), read under the account's lock together with whether the
    # account was suspended meanwhile. Disconnecting is Inclamo::Ai::Disconnect.
    class AgentConnection
      Result = Struct.new(:outcome, :record, keyword_init: true)

      # The request cannot be served for this store; `code` is the contract's.
      class Refused < StandardError
        STATUSES = {
          'no_account' => :not_found,
          'account_suspended' => :conflict,
          'agent_connected' => :conflict,
          'busy' => :conflict,
          'agent_refused' => :unprocessable_entity,
          'agent_not_answered' => :bad_gateway,
          'not_ready' => :service_unavailable
        }.freeze

        attr_reader :code, :details

        def initialize(code, details = {})
          @code = code
          @details = details
          super(code)
        end

        def status
          STATUSES.fetch(code)
        end
      end

      # How long the suspension waits for a connection or disconnection of the
      # account that is under way: a connection waits at most Ai::TIME_LIMIT
      # for the AI service.
      SUSPENSION_WAIT = 15
      SUSPENSION_POLL = 0.25

      # Wraps the suspension of the account (Removal): the agent is
      # disconnected before it, and once more after it in case the app's
      # connection was under way meanwhile (the connection itself refuses an
      # account it finds suspended under the lock). Not connected is no
      # failure, and an AI service that cannot be told is recorded on the
      # connection (`removal_error`) and stops nothing.
      def self.suspending(account, client: Ai::ServiceClient.new)
        return yield unless account

        disconnect_for_suspension(account, client)
        result = yield
        disconnect_for_suspension(account, client)
        result
      end

      def self.disconnect_for_suspension(account, client)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SUSPENSION_WAIT
        begin
          Ai::Disconnect.call(account: account, client: client)
        rescue Ai::Error::NotConnected
          nil
        rescue Ai::Error::Busy
          raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep SUSPENSION_POLL
          retry
        end
      end

      def initialize(shop_domain, client: Ai::ServiceClient.new)
        @shop_domain = shop_domain
        @client = client
      end

      # PUT: the store's account is connected to the agent. Answers
      # Result(outcome: 'connected' | 'existed', record:), or raises Refused.
      def connect(payload)
        row, account = store!
        refuse!('account_suspended') if suspended?(row, account)
        refuse!('not_ready') unless Chatwoot.encryption_configured?

        existing = Inclamo::AiConnection.active_for(account.id)
        return existed(existing, payload) if existing

        record = Ai::Connect.call(account: account, user: nil, pairing: payload.pairing, inbox_ids: -> { chosen_inboxes(row, account) },
                                  allow_no_inboxes: true, via: 'app', client: @client)
        Result.new(outcome: 'connected', record: record)
      rescue Ai::Error::AlreadyConnected
        # Another request connected the account between the look and the lock.
        existing = Inclamo::AiConnection.active_for(account.id)
        existing ? existed(existing, payload) : refuse!('busy')
      rescue Ai::Error::Busy, Ai::Error::InboxHasBot
        # Another connection or disconnection of the account is under way, or
        # the storefront inbox was given another bot while the AI service was asked.
        refuse!('busy')
      rescue Ai::Error::Refused => e
        refuse!('agent_refused', message: e.message, service_error: e.service_error)
      rescue Ai::Error::NotAnswered
        refuse!('agent_not_answered')
      rescue Ai::Error::EncryptionNotConfigured
        refuse!('not_ready')
      end

      # GET: the connection of the store's account, or that it never had one.
      def status
        _row, account = store!
        Inclamo::AiConnection.find_by(account_id: account.id)
      end

      # DELETE: the agent is disconnected. Answers [state, ai_service_told].
      def disconnect
        _row, account = store!
        record = Ai::Disconnect.call(account: account, client: @client)
        ['disconnected', record.removal_error.nil?]
      rescue Ai::Error::NotConnected
        [Inclamo::AiConnection.exists?(account_id: account.id) ? 'disconnected' : 'never_connected', true]
      rescue Ai::Error::Busy
        refuse!('busy')
      end

      # What the agent answers in now: the inboxes its bot is attached to, read
      # from the inboxes rather than from what was registered, so a connection
      # made again on the page with other inboxes is told as it is, and a
      # deleted inbox (whose link Chatwoot removes later) is not.
      def self.answering_inbox_ids(record)
        return [] unless record&.active? && record.agent_bot_id

        AgentBotInbox.active.joins(:inbox).where(agent_bot_id: record.agent_bot_id).order(:inbox_id).pluck(:inbox_id)
      end

      private

      def store!
        row = Provisioning.store_domain(@shop_domain) && ProvisionedAccount.for_store(@shop_domain)
        refuse!('no_account') unless row&.account

        [row, row.account]
      end

      def suspended?(row, account)
        row.suspended? || account.suspended?
      end

      # Read under the account's lock (Ai::Connect): an account suspended since
      # the first look is refused here, before anything is made.
      def chosen_inboxes(row, account)
        refuse!('account_suspended') if suspended?(row.reload, account.reload)

        inbox = AgentInbox.for(account)
        inbox ? [inbox.id] : []
      end

      # The same AI service: nothing is registered again, the token is not
      # used and the inboxes are not touched. Another one: refused.
      def existed(record, payload)
        refuse!('agent_connected') unless AgentServices.normalize(record.service_url) == payload.pairing.service_url

        Result.new(outcome: 'existed', record: record)
      end

      def refuse!(code, details = {})
        raise Refused.new(code, details)
      end
    end
  end
end
