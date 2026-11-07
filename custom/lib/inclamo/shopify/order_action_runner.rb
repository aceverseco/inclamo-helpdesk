# frozen_string_literal: true

module Inclamo
  module Shopify
    # Performs an order action for an agent and keeps the record of it.
    #
    # Order of things, each one a reason to stop:
    #   1. a record with this action id exists      -> its outcome, continued if it was open
    #      and no other request is working on it; refused when it belongs to
    #      another conversation, order or action
    #   2. the agent may not act, or the app lacks a scope -> refused, the store is not called
    #   3. the order is read; it does not allow the action  -> refused
    #   4. the record is written, then the store is asked
    # An accepted action leaves a private note in the conversation.
    #
    # One request at a time works on an attempt: the one that created it,
    # and later one that claims it (`claim!`). An attempt still pending after
    # LEASE belongs to a request that ended without finishing it.
    class OrderActionRunner
      HANDLERS = { 'cancel' => Actions::Cancel, 'address' => Actions::Address, 'refund' => Actions::Refund, 'replacement' => Actions::Replacement }.freeze
      LEASE = 5.minutes

      # `connection` is the account's store connection when the caller has it already.
      def initialize(account:, account_user:, conversation:, connection: nil)
        @account = account
        @account_user = account_user
        @conversation = conversation
        @connection = connection || ShopifyConnection.find_by(account_id: account.id)
      end

      # `extra` is what must not be recorded (the new address). `macro_id`
      # names the macro an order step runs in.
      def perform(action:, action_id:, order_id:, params: {}, extra: {}, macro_id: nil)
        action = action.to_s
        existing = OrderAction.find_by(account_id: @account.id, action_id: action_id.to_s)
        return taken(action, action_id, order_id) if existing && !same_attempt?(existing, action, order_id)
        return settle(existing, extra) if existing

        record = OrderAction.new(account: @account, conversation: @conversation, user: @account_user&.user, action_id: action_id.to_s,
                                 action: action, order_id: order_id.to_s, params: recordable(action, params), macro_id: macro_id)
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

      # What a refund would be, for the confirmation: nothing is changed and
      # nothing is recorded. Raises Actions::Refused with the reason when the
      # agent, the connection or the order does not allow it.
      def refund_preview(order_id:, params:)
        refund_plan(allowed_order!('refund', order_id), params)
      end

      # What an action with these parameters would do to the order, for the
      # confirmation of a macro: the money a refund or a cancellation gives
      # back, the units a replacement sends. Nothing is changed and nothing is
      # recorded. When the action would be refused, says why instead.
      def step_preview(action:, order_id:, params:)
        order = allowed_order!(action, order_id)
        case action.to_s
        when 'refund' then refund_plan(order, params).slice(:amount, :currency)
        when 'cancel' then cancellation_refund(order, params)
        when 'replacement' then { units: Actions::Replacement.units_left(order) }
        else {}
        end
      rescue Actions::Refused, Error => e
        refused = self.class.refusal_for(e)
        refused[:missing_scopes] = @connection.missing_scopes_for(action) if refused[:refusal] == 'missing_scope'
        refused
      end

      # The refusal an error of an order action stands for, as records and
      # confirmations name it: the code, the store's words, and for a store
      # that could not be reached the kind of failure.
      def self.refusal_for(error)
        case error
        when Actions::Refused then { refusal: error.code, message: (error.message unless error.message == error.code) }
        # The store understood the request and said no, in words.
        when Error::QueryError then { refusal: 'store_refused', message: error.message.first(500) }
        else { refusal: 'store_unreachable', message: nil, reason: error.class.name.demodulize.underscore }
        end
      end

      # Settles what an earlier request left open, e.g. a cancellation the
      # store was still working on, by reading the store: nothing is sent to
      # it again. Called when the panel is read.
      def settle_open!
        OrderAction.unsettled.where(account_id: @account.id, conversation_id: @conversation.id).find_each { |record| resolve(record) }
      end

      private

      def reader
        @reader ||= OrderReader.new(@connection)
      end

      # The order, when this agent may perform this action on it. Raises
      # Actions::Refused with the reason otherwise.
      def allowed_order!(action, order_id)
        refusal = gate(action.to_s)
        raise Actions::Refused, refusal if refusal

        order = reader.order(order_id.to_s) or raise Actions::Refused, 'unknown_order'
        refusal = OrderPresenter.new(order, shop_domain: @connection.shop_domain).refusal(action)
        raise Actions::Refused, refusal if refusal

        order
      end

      def refund_plan(order, params)
        draft = OrderAction.new(action: 'refund', order_id: order['id'], action_id: 'preview', params: recordable('refund', params))
        Actions::Refund.new(store: StoreConnection.new(@connection), record: draft, order: order).preview
      end

      # What a cancellation gives back: everything that remains when it
      # refunds. Without an amount, `refund` says why: nothing was paid,
      # everything paid was refunded already, or the amount could not be
      # worked out now, which does not stop the cancellation itself.
      def cancellation_refund(order, params)
        return {} unless params.to_h.stringify_keys['refund'] == true
        return { refund: 'unpaid' } unless order.dig('totalReceivedSet', 'shopMoney', 'amount').to_d.positive?
        return { refund: 'none_left' } unless OrderPresenter.new(order, shop_domain: '').refundable_amount.positive?

        refund_plan(order, { 'mode' => 'full' }).slice(:amount, :currency)
      rescue Actions::Refused, Error
        { refund: 'unknown' }
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

      # The id belongs to an attempt in another conversation, or for another
      # order or action. Answered as a refusal that is not recorded: the id is
      # that attempt's, and nothing of it is shown here.
      def same_attempt?(existing, action, order_id)
        existing.conversation_id == @conversation&.id && existing.action == action && existing.order_id.to_s == order_id.to_s
      end

      def taken(action, action_id, order_id)
        OrderAction.new(account: @account, action_id: action_id.to_s, action: action, order_id: order_id.to_s, outcome: 'refused', refusal: 'action_id_taken')
      end

      # A repeated request: continues an open attempt, unless another request
      # is working on it right now.
      def settle(record, extra)
        return record if record.settled?
        # An address is not recorded, so an open address change cannot be repeated from the record.
        return record if record.action == 'address' && extra.blank?
        return record if gate(record.action)

        order = reader.order(record.order_id)
        return record unless order
        return record unless claim!(record)

        run(record, order, extra)
      rescue Error
        record
      end

      # Takes an open attempt for this request, as it was read: one that is
      # running or unknown, or pending longer than LEASE. False when another
      # request has it, or has moved it on since.
      def claim!(record)
        open = record.outcome != 'pending' || record.updated_at < LEASE.ago
        return false unless open && %w[pending running unknown].include?(record.outcome)

        claimed = OrderAction.where(id: record.id, outcome: record.outcome, updated_at: record.updated_at)
                             .update_all(outcome: 'pending', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        record.reload
        claimed == 1
      end

      # Settles an open attempt by reading the store (D7): the handlers of
      # this file `resolve` without asking the store to act. An attempt whose
      # request ended without finishing it, and that the store does not
      # settle, is unknown.
      def resolve(record)
        was = record.outcome
        return unless claim!(record)

        order = reader.order(record.order_id)
        state = order && handler_for_reading(record, order).resolve
        case state
        when :accepted then accept!(record)
        when :running then record.update!(outcome: 'running')
        else record.update!(outcome: was == 'pending' ? 'unknown' : was)
        end
        OrderReader.forget!(@account.id) if record.settled?
      rescue Actions::Refused => e
        record.update!(outcome: 'refused', refusal: e.code, store_message: e.message == e.code ? record.store_message : e.message, completed_at: Time.current)
        OrderReader.forget!(@account.id)
      rescue Error
        # The store could not be read: the attempt is left as it was.
        record.update!(outcome: was == 'pending' ? 'unknown' : was)
      end

      def handler_for_reading(record, order)
        arguments = { store: StoreConnection.new(@connection), record: record, order: order }
        arguments[:address] = nil if record.action == 'address'
        arguments[:shop_domain] = @connection.shop_domain if record.action == 'replacement'
        HANDLERS.fetch(record.action).new(**arguments)
      end

      def run(record, order, extra)
        handler = HANDLERS.fetch(record.action)
        arguments = { store: StoreConnection.new(@connection), record: record, order: order }
        arguments[:address] = extra[:address] || extra['address'] if record.action == 'address'
        arguments[:shop_domain] = @connection.shop_domain if record.action == 'replacement'
        state = handler.new(**arguments).call
        state == :running ? record.update!(outcome: 'running') : accept!(record)
        record
      rescue Actions::Refused, Error => e
        # A lost answer is neither done nor failed; anything else is a refusal.
        if e.is_a?(Error) && e.outcome_unknown?
          record.update!(outcome: 'unknown', store_message: e.class.name.demodulize.underscore)
        else
          refused = self.class.refusal_for(e)
          record.update!(outcome: 'refused', refusal: refused[:refusal], store_message: refused[:message] || refused[:reason], completed_at: Time.current)
        end
        record
      ensure
        OrderReader.forget!(@account.id)
      end

      def accept!(record)
        record.update!(outcome: 'accepted', completed_at: Time.current)
        note!(record)
      end

      # A private note in the conversation of the action, written as the agent who acted.
      def note!(record)
        conversation = record.conversation
        return if record.note_message_id || conversation.nil? || record.user.nil?

        content = I18n.t("inclamo.order_actions.notes.#{record.action}", **note_facts(record))
        message = Messages::MessageBuilder.new(record.user, conversation, { content: content, private: true }).perform
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
