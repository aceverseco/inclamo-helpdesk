# frozen_string_literal: true

module Inclamo
  module Shopify
    # Performs an order action for an agent and keeps the record of it.
    #
    # Order of things, each one a reason to stop:
    #   1. a record with this action id exists      -> its outcome, settled if it was open
    #   2. the agent may not act, or the app lacks a scope -> refused, the store is not called
    #   3. the order (or, for a customer's tags and note, the customer) is read;
    #      it does not allow the action                    -> refused
    #   4. the record is written, then the store is asked
    # An accepted action leaves a private note in the conversation.
    class OrderActionRunner
      HANDLERS = {
        'cancel' => Actions::Cancel, 'address' => Actions::Address, 'refund' => Actions::Refund, 'replacement' => Actions::Replacement,
        'order_tags' => Actions::Tags, 'customer_tags' => Actions::Tags, 'order_note' => Actions::Note, 'customer_note' => Actions::Note
      }.freeze
      # The text of a note is not recorded: an open change of it cannot be repeated from the record.
      NOTE_ACTIONS = %w[order_note customer_note].freeze

      def initialize(account:, account_user:, conversation:)
        @account = account
        @account_user = account_user
        @conversation = conversation
        @connection = ShopifyConnection.find_by(account_id: account.id)
      end

      # `extra` is what must not be recorded (the new address, the text of a note).
      # A customer's tags and note are changed with `customer_id` instead of `order_id`.
      def perform(action:, action_id:, order_id: nil, customer_id: nil, params: {}, extra: {})
        action = action.to_s
        existing = OrderAction.find_by(account_id: @account.id, action_id: action_id.to_s)
        return settle(existing, extra) if existing

        record = OrderAction.new(account: @account, conversation: @conversation, user: @account_user&.user, action_id: action_id.to_s,
                                 action: action, order_id: order_id.to_s.presence, customer_id: customer_id.to_s.presence,
                                 params: recordable(action, params))
        refusal = gate(action)
        return refuse!(record, refusal) if refusal

        subject = read(record)
        return refuse!(record, record.customer_action? ? 'unknown_customer' : 'unknown_order') unless subject

        unless record.customer_action?
          record.order_number = subject['name']
          refusal = OrderPresenter.new(subject, shop_domain: @connection.shop_domain).refusal(action)
          return refuse!(record, refusal) if refusal
        end

        record.save! # before the store is asked to change anything
        run(record, subject, extra)
      rescue Error => e
        # The store could not be read: nothing was attempted.
        refuse!(record, 'store_unreachable', e.class.name.demodulize.underscore)
      end

      # What a refund would be, for the confirmation: nothing is changed and
      # nothing is recorded. Raises Actions::Refused with the reason when the
      # agent, the connection or the order does not allow it.
      def refund_preview(order_id:, params:)
        refusal = gate('refund')
        raise Actions::Refused, refusal if refusal

        order = reader.order(order_id.to_s) or raise Actions::Refused, 'unknown_order'
        refusal = OrderPresenter.new(order, shop_domain: @connection.shop_domain).refusal('refund')
        raise Actions::Refused, refusal if refusal

        draft = OrderAction.new(action: 'refund', order_id: order['id'], action_id: 'preview', params: recordable('refund', params))
        Actions::Refund.new(store: StoreConnection.new(@connection), record: draft, order: order).preview
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

      # What the action is about, read from the store: the order (through the
      # minute's cache), or the customer as the store holds it now.
      def read(record)
        record.customer_action? ? reader.customer_marks(record.customer_id) : reader.order(record.order_id)
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
        return record if NOTE_ACTIONS.include?(record.action) && note_from(extra).nil?
        return record if gate(record.action)

        subject = read(record)
        return record unless subject

        run(record, subject, extra)
      rescue Error
        record
      end

      def run(record, order, extra)
        handler = HANDLERS.fetch(record.action)
        arguments = { store: StoreConnection.new(@connection), record: record, order: order }
        arguments[:address] = extra[:address] || extra['address'] if record.action == 'address'
        arguments[:note] = note_from(extra) if NOTE_ACTIONS.include?(record.action)
        arguments[:shop_domain] = @connection.shop_domain if record.action == 'replacement'
        state = handler.new(**arguments).call
        state == :running ? record.update!(outcome: 'running') : accept!(record)
        record
      rescue Actions::Refused => e
        record.update!(outcome: 'refused', refusal: e.code, store_message: (e.message unless e.message == e.code), completed_at: Time.current)
        record
      rescue Error::QueryError => e
        # The store understood the request and said no, in words.
        record.update!(outcome: 'refused', refusal: 'store_refused', store_message: e.message.first(500), completed_at: Time.current)
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

        content = I18n.t("inclamo.order_actions.notes.#{note_key(record)}", **note_facts(record))
        message = Messages::MessageBuilder.new(record.user, @conversation, { content: content, private: true }).perform
        record.update_columns(note_message_id: message.id) # rubocop:disable Rails/SkipsModelValidations
      end

      def note_from(extra)
        extra[:note].nil? ? extra['note'] : extra[:note]
      end

      # A tag's note says whether it was added or removed.
      def note_key(record)
        %w[order_tags customer_tags].include?(record.action) ? "#{record.action}_#{record.params['operation']}" : record.action
      end

      def note_facts(record)
        params = record.params
        details = []
        details << I18n.t('inclamo.order_actions.notes.details.reason', reason: params['reason'].to_s.downcase) if params['reason'].present?
        details << I18n.t('inclamo.order_actions.notes.details.refunded') if params['refund'] == true
        details << I18n.t('inclamo.order_actions.notes.details.restocked') if params['restock'] == true
        details << I18n.t('inclamo.order_actions.notes.details.notified') if params['notify'] == true
        { number: record.order_number, tag: params['tag'], details: details.join(' ') }.merge(record.progress.slice('new_order_number', 'refunded').symbolize_keys)
      end
    end
  end
end
