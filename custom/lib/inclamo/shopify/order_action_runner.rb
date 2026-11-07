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
    #
    # An order-less action (OrderAction::ORDER_LESS, e.g. a new order) skips
    # step 3: it is about the customer matched to the conversation, whom its
    # handler gets with `customer:`. The handler's `refusal` replaces the
    # order's, and its record has no order id.
    class OrderActionRunner
      HANDLERS = { 'cancel' => Actions::Cancel, 'address' => Actions::Address, 'refund' => Actions::Refund, 'replacement' => Actions::Replacement,
                   'new_order' => Actions::NewOrder, 'discount' => Actions::Discount }.freeze

      def initialize(account:, account_user:, conversation:)
        @account = account
        @account_user = account_user
        @conversation = conversation
        @connection = ShopifyConnection.find_by(account_id: account.id)
      end

      # `extra` is what must not be recorded (the new address, a new order's note).
      def perform(action:, action_id:, order_id:, params: {}, extra: {})
        action = action.to_s
        existing = OrderAction.find_by(account_id: @account.id, action_id: action_id.to_s)
        return settle(existing, extra) if existing

        record = OrderAction.new(account: @account, conversation: @conversation, user: @account_user&.user, action_id: action_id.to_s,
                                 action: action, order_id: order_id.to_s.presence, params: recordable(action, params))
        refusal = gate(action)
        return refuse!(record, refusal) if refusal
        return perform_order_less(record, extra) if record.order_less?

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
        refusal = gate('refund')
        raise Actions::Refused, refusal if refusal

        order = reader.order(order_id.to_s) or raise Actions::Refused, 'unknown_order'
        refusal = OrderPresenter.new(order, shop_domain: @connection.shop_domain).refusal('refund')
        raise Actions::Refused, refusal if refusal

        draft = OrderAction.new(action: 'refund', order_id: order['id'], action_id: 'preview', params: recordable('refund', params))
        Actions::Refund.new(store: StoreConnection.new(@connection), record: draft, order: order).preview
      end

      # What a new order would cost, as the store calculates it, for the
      # summary: nothing is created and nothing is recorded. Raises
      # Actions::Refused like refund_preview.
      def new_order_preview(params:)
        refusal = gate('new_order')
        raise Actions::Refused, refusal if refusal

        draft = OrderAction.new(action: 'new_order', action_id: 'preview', params: recordable('new_order', params))
        handler = Actions::NewOrder.new(store: StoreConnection.new(@connection), record: draft, customer: matched_customer)
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

      # Finishes what an earlier request left open, e.g. a cancellation the
      # store was still working on. Called when the panel is read.
      def settle_open!
        OrderAction.unsettled.where(account_id: @account.id, conversation_id: @conversation.id).find_each { |record| settle(record, {}) }
      end

      private

      def reader
        @reader ||= OrderReader.new(@connection)
      end

      def perform_order_less(record, extra)
        customer = matched_customer
        refusal = HANDLERS.fetch(record.action).new(store: StoreConnection.new(@connection), record: record, customer: customer).refusal
        return refuse!(record, refusal) if refusal

        record.save! # before the store is asked to change anything
        run(record, nil, extra.merge(customer: customer))
      end

      # The store's customer matched to the conversation's contact, with their
      # email and phone, or nil when there is no single match.
      def matched_customer
        contact = @conversation&.contact
        return unless contact

        match = CustomerMatcher.new(reader, contact, limited: @connection.customer_data_limited?).call
        reader.customer_with_orders(match.customer_id) if match.state == 'matched'
      end

      def recordable(action, params)
        handler = HANDLERS[action]
        handler ? handler.recordable(params.to_h.stringify_keys) : {}
      end

      # Why this agent cannot perform this action with this connection, or nil.
      # Decided without calling the store.
      def gate(action)
        return 'unknown_action' unless HANDLERS.key?(action)
        # Giving discounts is its own right, apart from the order-actions role.
        allowed = action == 'discount' ? DiscountGrant.allows?(@account_user) : OrderRole.allows?(@account_user)
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

      def settle(record, extra)
        return record if record.settled?
        # An address is not recorded, so an open address change cannot be repeated from the record.
        return record if record.action == 'address' && extra.blank?
        return record if gate(record.action)

        order = record.order_less? ? nil : reader.order(record.order_id)
        return record unless order || record.order_less?

        run(record, order, extra)
      rescue Error
        record
      end

      def run(record, order, extra)
        handler = HANDLERS.fetch(record.action)
        arguments = { store: StoreConnection.new(@connection), record: record, order: order }
        arguments[:address] = extra[:address] || extra['address'] if record.action == 'address'
        arguments[:shop_domain] = @connection.shop_domain if record.action == 'replacement'
        arguments.merge!(customer: extra[:customer], note: extra[:note] || extra['note']) if record.action == 'new_order'
        # Only the request that started a discount creates its code; settling one looks it up.
        arguments.merge!(customer: extra[:customer], starting: extra.key?(:customer)) if record.action == 'discount'
        state = handler.new(**arguments).call
        case state
        when :running then record.update!(outcome: 'running')
        # Not decided yet (a lost new order the store's search may not show yet).
        when :unknown then record.update!(outcome: 'unknown')
        else accept!(record)
        end
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
        facts = { number: record.order_number, details: details.join(' ') }.merge(record.progress.slice('new_order_number', 'refunded').symbolize_keys)
        case record.action
        when 'new_order' then facts.merge(new_order_facts(record))
        when 'discount' then facts.merge(discount_facts(record))
        else facts
        end
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

      # The draft, its total and how the payment link reached the customer; no customer data.
      def new_order_facts(record)
        total = record.progress['total'] || {}
        delivered = record.progress['invoice_sent'] ? 'invoice_emailed' : 'link_in_reply'
        { draft_name: record.progress['draft_name'], total: [total['amount'], total['currency']].compact.join(' '),
          delivery: I18n.t("inclamo.order_actions.notes.details.#{delivered}") }
      end
    end
  end
end
