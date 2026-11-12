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
    #   3. the order (or, for a customer's tags and note, the customer) is read;
    #      it does not allow the action                    -> refused
    #   4. the record is written, then the store is asked
    # An accepted action leaves a private note in the conversation.
    #
    # One request at a time works on an attempt: the one that created it,
    # and later one that claims it (`claim!`, held in `claimed_at`). An attempt
    # still pending, or still claimed, after LEASE belongs to a request that
    # ended without finishing it.
    #
    # An order-less action (OrderAction::ORDER_LESS, e.g. a new order) skips
    # step 3: it is about the customer matched to the conversation, whom its
    # handler gets with `customer:`. The handler's `refusal` replaces the
    # order's, and its record has no order id.
    #
    # What a handler is given besides the store, the record and the order it
    # declares itself (`context`), so that this file knows no action by name.
    class OrderActionRunner
      HANDLERS = {
        'cancel' => Actions::Cancel, 'address' => Actions::Address, 'refund' => Actions::Refund, 'replacement' => Actions::Replacement,
        'order_tags' => Actions::Tags, 'customer_tags' => Actions::Tags, 'order_note' => Actions::Note, 'customer_note' => Actions::Note, 'new_order' => Actions::NewOrder, 'edit_items' => Actions::EditItems, 'discount' => Actions::Discount
      }.freeze
      LEASE = 5.minutes
      NOTE_ACTIONS = %w[order_note customer_note].freeze
      # What became of the invoice after an items edit, as its note says it.
      EDIT_INVOICE_NOTES = { 'sent' => 'invoice_emailed', 'refused' => 'invoice_refused', 'unknown' => 'invoice_unknown' }.freeze

      # `connection` is the account's store connection when the caller has it already.
      def initialize(account:, account_user:, conversation:, connection: nil, authorizer: nil, ai_proposal: nil, matched_customer_id: nil)
        @account = account
        @account_user = account_user
        @conversation = conversation
        @connection = connection || ShopifyConnection.find_by(account_id: account.id)
        @authorizer = authorizer
        @ai_proposal = ai_proposal
        @matched_customer_id = matched_customer_id
      end

      # `extra` holds the address and note that must not be recorded.
      def perform(action:, action_id:, order_id: nil, customer_id: nil, params: {}, extra: {}, macro_id: nil)
        action = action.to_s
        existing = OrderAction.find_by(account_id: @account.id, action_id: action_id.to_s)
        return taken(action, action_id, order_id) if existing && !same_attempt?(existing, action, order_id, customer_id)
        return settle(existing, extra) if existing

        record = OrderAction.new(account: @account, conversation: @conversation, user: @account_user&.user, action_id: action_id.to_s,
                                 action: action, order_id: order_id.to_s.presence, customer_id: customer_id.to_s.presence,
                                 params: recordable(action, params), macro_id: macro_id, ai_proposal_id: @ai_proposal&.id)
        refusal = gate(action, record.params)
        return refuse!(record, refusal) if refusal
        return perform_order_less(record, extra) if record.order_less?

        subject = read(record)
        return refuse!(record, record.customer_action? ? 'unknown_customer' : 'unknown_order') unless subject

        unless record.customer_action?
          record.order_number = subject['name']
          refusal = OrderPresenter.new(subject, shop_domain: @connection.shop_domain).refusal(action)
          return refuse!(record, refusal) if refusal
        end

        record.save! # before the store is asked to change anything
        run(record, handler_for(record, subject, extra))
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
        order = allowed_order!(action, order_id, params)
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

      # What a new order would cost, as the store calculates it, for the
      # summary: nothing is created and nothing is recorded. Raises
      # Actions::Refused like refund_preview.
      def new_order_preview(params:)
        refusal = gate('new_order', params)
        raise Actions::Refused, refusal if refusal

        draft = OrderAction.new(action: 'new_order', action_id: 'preview', params: recordable('new_order', params))
        handler = handler_for(draft, nil, { customer: matched_customer })
        refusal = handler.refusal(preview: true)
        raise Actions::Refused, refusal if refusal

        handler.preview
      end

      # The items of an order of the matched customer, to start a new order
      # from ("order again"). Raises Actions::Refused like refund_preview.
      def new_order_prefill(order_id:)
        refusal = gate('new_order')
        raise Actions::Refused, refusal if refusal

        customer = matched_customer or raise Actions::Refused, 'no_customer'
        raise Actions::Refused, 'unknown_order' unless order_id.to_s.match?(OrderReader::ORDER_ID)

        order = StoreConnection.new(@connection).query(:new_order_from_order, { id: order_id.to_s })['order']
        raise Actions::Refused, 'unknown_order' unless order
        raise Actions::Refused, 'not_customers_order' unless order.dig('customer', 'id') == customer['id']

        Actions::NewOrder.prefill(order, currency: @connection.shop_currency)
      end

      # What an edit of the items would make of the order, for the summary.
      # The store calculates it in a session that is never committed.
      def edit_items_preview(order_id:, params:)
        order = allowed_order!('edit_items', order_id)
        draft = OrderAction.new(action: 'edit_items', order_id: order['id'], action_id: 'preview', params: recordable('edit_items', params))
        Actions::EditItems.new(store: StoreConnection.new(@connection), record: draft, order: order).preview
      end

      # Settles what an earlier request left open, e.g. a cancellation the
      # store was still working on, by reading the store: nothing is sent to
      # it again. Called when the panel is read.
      def settle_open!
        OrderAction.unsettled.where(account_id: @account.id, conversation_id: @conversation.id).find_each { |record| resolve(record) }
      end

      private

      # The order for a preview of an action, read when the agent, the
      # connection and the order allow the action; Actions::Refused otherwise.
      def previewable!(action, order_id)
        refusal = gate(action)
        raise Actions::Refused, refusal if refusal

        order = reader.order(order_id.to_s) or raise Actions::Refused, 'unknown_order'
        refusal = OrderPresenter.new(order, shop_domain: @connection.shop_domain).refusal(action)
        raise Actions::Refused, refusal if refusal

        order
      end

      def reader
        @reader ||= OrderReader.new(@connection)
      end

      # What the action is about, read from the store: the order (through the
      # minute's cache), or the customer as the store holds it now.
      def read(record)
        record.customer_action? ? reader.customer_marks(record.customer_id) : reader.order(record.order_id)
      end

      def perform_order_less(record, extra)
        handler = handler_for(record, nil, extra.merge(customer: matched_customer))
        refusal = handler.refusal
        return refuse!(record, refusal) if refusal

        record.save! # before the store is asked to change anything
        run(record, handler)
      end

      # The store's customer matched to the conversation's contact, with their
      # email and phone, or nil when there is no single match.
      def matched_customer
        return reader.customer_with_orders(@matched_customer_id) if @matched_customer_id

        contact = @conversation&.contact
        return unless contact

        match = CustomerMatcher.new(reader, contact, limited: @connection.customer_data_limited?).call
        reader.customer_with_orders(match.customer_id) if match.state == 'matched'
      end

      # The order, when this agent may perform this action on it. Raises
      # Actions::Refused with the reason otherwise.
      def allowed_order!(action, order_id, params = {})
        refusal = gate(action.to_s, params)
        raise Actions::Refused, refusal if refusal

        order = reader.order(order_id.to_s) or raise Actions::Refused, 'unknown_order'
        refusal = OrderPresenter.new(order, shop_domain: @connection.shop_domain).refusal(action)
        raise Actions::Refused, refusal if refusal

        order
      end

      def refund_plan(order, params)
        draft = OrderAction.new(action: 'refund', order_id: order['id'], action_id: 'preview', params: recordable('refund', params))
        handler_for(draft, order).preview
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
      def gate(action, params = {})
        return 'unknown_action' unless HANDLERS.key?(action)
        # Giving discounts is its own right, apart from the order-actions role.
        allowed = @authorizer ? @authorizer.call(action, params) : ActionPermissions.allows?(@account_user, action, params)
        return 'not_allowed' unless allowed
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
      def same_attempt?(existing, action, order_id, customer_id)
        existing.conversation_id == @conversation&.id && existing.action == action && existing.order_id.to_s == order_id.to_s && existing.customer_id.to_s == customer_id.to_s
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
        return record if NOTE_ACTIONS.include?(record.action) && note_from(extra).nil?
        return record if gate(record.action, record.params)

        handler = handler_for_open(record, extra)
        return record unless handler
        return record unless (claimed = claim!(record))

        run(record, handler)
      rescue Error
        record
      ensure
        release!(record) if claimed
      end

      # Takes an open attempt for this request, as it was read: one that is
      # running or unknown, or pending longer than LEASE, and that no other
      # request holds (claimed less than LEASE ago). Its outcome is left as it
      # is, so that a panel read meanwhile still shows a running cancellation
      # as running. False when another request has it, or has moved it on since.
      def claim!(record)
        open = record.outcome != 'pending' || record.updated_at < LEASE.ago
        return false unless open && %w[pending running unknown].include?(record.outcome)
        return false if record.claimed_at && record.claimed_at >= LEASE.ago

        now = Time.current
        claimed = OrderAction.where(id: record.id, outcome: record.outcome, updated_at: record.updated_at)
                             .update_all(claimed_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
        record.reload
        claimed == 1
      end

      # Ends this request's hold on an attempt it claimed, unless the hold ran
      # out and another request holds it now.
      def release!(record)
        OrderAction.where(id: record.id, claimed_at: record.claimed_at).update_all(claimed_at: nil) # rubocop:disable Rails/SkipsModelValidations
      end

      # Settles an open attempt by reading the store (D7): the handlers of
      # this file `resolve` without asking the store to act. An attempt whose
      # request ended without finishing it, and that the store does not
      # settle, is unknown.
      def resolve(record)
        was = record.outcome
        return unless (claimed = claim!(record))

        state = handler_for_open(record)&.resolve
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
      ensure
        release!(record) if claimed
      end

      def handler_for(record, order, extra = {})
        handler = HANDLERS.fetch(record.action)
        handler.new(store: StoreConnection.new(@connection), record: record, order: order, **handler.context(connection: @connection, extra: extra))
      end

      # The handler of an open attempt, with its order read again; nil when
      # the store no longer has the order. An order-less attempt reads none.
      def handler_for_open(record, extra = {})
        return handler_for(record, nil, extra) if record.order_less?

        subject = read(record)
        subject && handler_for(record, subject, extra)
      end

      def run(record, handler)
        state = handler.call
        case state
        when :running then record.update!(outcome: 'running')
        # Not decided yet: the store may or may not have acted (a lost new order its search
        # may not show yet, a lost edit). Settled again when the panel is read.
        when :unknown then record.update!(outcome: 'unknown')
        else accept!(record)
        end
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
        proposal = Inclamo::AiProposal.find_by(id: record.ai_proposal_id) if record.ai_proposal_id
        sender = record.user || proposal&.agent_bot
        return if record.note_message_id || conversation.nil? || sender.nil?

        content = I18n.t("inclamo.order_actions.notes.#{note_key(record)}", **note_facts(record)).squish
        if proposal
          approver = proposal.approved_by
          content = "AI: #{proposal.agent_bot.name}. #{approver ? "Approved by #{approver.name}." : 'Autonomous action.'} #{content}"
        end
        message = Messages::MessageBuilder.new(sender, conversation, { content: content, private: true }).perform
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
        invoice = EDIT_INVOICE_NOTES[record.progress['invoice']]
        details << I18n.t("inclamo.order_actions.notes.details.#{invoice}") if invoice
        facts = { number: record.order_number, tag: params['tag'], details: details.join(' ') }.merge(record.progress.slice('new_order_number', 'refunded').symbolize_keys)
        return facts.merge(discount_facts(record)) if record.action == 'discount'

        facts.merge(HANDLERS.fetch(record.action).note_facts(record)).merge(edit_facts(record))
      end

      # The code and the conditions copied from its preset; no customer data.
      def discount_facts(record)
        params = record.params
        scope = 'inclamo.order_actions.notes.discount_details'
        value = params['kind'] == 'percentage' ? "#{params['value']}%" : "#{format('%.2f', params['value'].to_d)} #{@connection.shop_currency}".strip
        expiry = params['expires_at'] ? I18n.t("#{scope}.expires", date: Time.zone.parse(params['expires_at']).to_date.iso8601) : I18n.t("#{scope}.never")
        { code: record.progress['code'] || params['code'], preset: params['preset_name'], value: value,
          uses: I18n.t("#{scope}.uses", count: params['usage_limit'].to_i), audience: I18n.t("#{scope}.audience.#{params['audience']}"), expiry: expiry }
      end

      # The changes of an items edit and what they mean for the money.
      def edit_facts(record)
        return {} unless record.action == 'edit_items'

        progress = record.progress
        money = I18n.t("inclamo.order_actions.notes.edit.money.#{progress['difference'] || 'none'}", amount: "#{progress['amount']} #{progress['currency']}")
        { changes: Array(progress['changes']).join('; '), money: money }
      end
    end
  end
end
