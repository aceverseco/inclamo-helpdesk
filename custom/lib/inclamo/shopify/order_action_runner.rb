# frozen_string_literal: true

module Inclamo
  module Shopify
    # Performs an order action for an agent and keeps the record of it.
    #
    # Order of things, each one a reason to stop:
    #   1. a record with this action id exists      -> its outcome, settled if it was open
    #   2. the agent may not act, or the app lacks a scope -> refused, the store is not called
    #   3. the order is read; it does not allow the action  -> refused
    #   4. the record is written, then the store is asked
    # An accepted action leaves a private note in the conversation.
    class OrderActionRunner
      HANDLERS = { 'cancel' => Actions::Cancel, 'address' => Actions::Address }.freeze

      def initialize(account:, account_user:, conversation:)
        @account = account
        @account_user = account_user
        @conversation = conversation
        @connection = ShopifyConnection.find_by(account_id: account.id)
      end

      # `extra` is what must not be recorded (the new address).
      def perform(action:, action_id:, order_id:, params: {}, extra: {})
        action = action.to_s
        existing = OrderAction.find_by(account_id: @account.id, action_id: action_id.to_s)
        return settle(existing, extra) if existing

        record = OrderAction.new(account: @account, conversation: @conversation, user: @account_user&.user, action_id: action_id.to_s,
                                 action: action, order_id: order_id.to_s, params: recordable(action, params))
        refusal = gate(action)
        return refuse!(record, refusal) if refusal

        order = reader.order(order_id.to_s)
        return refuse!(record, 'unknown_order') unless order

        record.order_number = order['name']
        refusal = OrderPresenter.new(order, shop_domain: @connection.shop_domain).refusal(action)
        return refuse!(record, refusal) if refusal

        record.save! # before the store is asked to change anything
        run(record, order, extra)
      rescue Error => e
        # The store could not be read: nothing was attempted.
        refuse!(record, 'store_unreachable', e.class.name.demodulize.underscore)
      end

      # Finishes what an earlier request left open, e.g. a cancellation the
      # store was still working on. Called when the panel is read.
      def settle_open!
        OrderAction.unsettled.where(account_id: @account.id, conversation_id: @conversation.id).find_each { |record| settle(record, {}) }
      end

      private

      def reader
        @reader ||= OrderReader.new(@connection)
      end

      def recordable(action, params)
        handler = HANDLERS[action]
        handler ? handler.recordable(params.to_h.stringify_keys) : {}
      end

      # Why this agent cannot perform this action with this connection, or nil.
      # Decided without calling the store.
      def gate(action)
        return 'unknown_action' unless HANDLERS.key?(action)
        return 'not_allowed' unless OrderRole.allows?(@account_user)
        return 'not_connected' unless @connection
        return 'connection_broken' if @connection.broken?

        @connection.unavailable_reason(action)
      end

      def refuse!(record, refusal, message = nil)
        record.assign_attributes(outcome: 'refused', refusal: refusal, store_message: message, completed_at: Time.current)
        record.save! if record.valid?
        record
      end

      def settle(record, extra)
        return record if record.settled?
        # An address is not recorded, so an open address change cannot be repeated from the record.
        return record if record.action == 'address' && extra.blank?
        return record if gate(record.action)

        order = reader.order(record.order_id)
        return record unless order

        run(record, order, extra)
      rescue Error
        record
      end

      def run(record, order, extra)
        handler = HANDLERS.fetch(record.action)
        arguments = { store: StoreConnection.new(@connection), record: record, order: order }
        arguments[:address] = extra[:address] || extra['address'] if record.action == 'address'
        state = handler.new(**arguments).call
        state == :running ? record.update!(outcome: 'running') : accept!(record)
        record
      rescue Actions::Refused => e
        record.update!(outcome: 'refused', refusal: e.code, store_message: (e.message unless e.message == e.code), completed_at: Time.current)
        record
      rescue Error => e
        # A lost answer is neither done nor failed; anything else never reached the store.
        if e.outcome_unknown?
          record.update!(outcome: 'unknown', store_message: e.class.name.demodulize.underscore)
        else
          record.update!(outcome: 'refused', refusal: 'store_unreachable', store_message: e.class.name.demodulize.underscore, completed_at: Time.current)
        end
        record
      ensure
        OrderReader.forget!(@account.id)
      end

      def accept!(record)
        record.update!(outcome: 'accepted', completed_at: Time.current)
        note!(record)
      end

      # A private note in the conversation, written as the agent who acted.
      def note!(record)
        return if record.note_message_id || @conversation.nil? || record.user.nil?

        content = I18n.t("inclamo.order_actions.notes.#{record.action}", **note_facts(record))
        message = Messages::MessageBuilder.new(record.user, @conversation, { content: content, private: true }).perform
        record.update_columns(note_message_id: message.id) # rubocop:disable Rails/SkipsModelValidations
      end

      def note_facts(record)
        params = record.params
        details = []
        details << I18n.t('inclamo.order_actions.notes.details.reason', reason: params['reason'].to_s.downcase) if params['reason'].present?
        details << I18n.t('inclamo.order_actions.notes.details.refunded') if params['refund'] == true
        details << I18n.t('inclamo.order_actions.notes.details.restocked') if params['restock'] == true
        details << I18n.t('inclamo.order_actions.notes.details.notified') if params['notify'] == true
        { number: record.order_number, details: details.join(' ') }.merge(record.progress.slice('new_order_number', 'refunded').symbolize_keys)
      end
    end
  end
end
