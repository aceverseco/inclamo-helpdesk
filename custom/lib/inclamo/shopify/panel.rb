# frozen_string_literal: true

module Inclamo
  module Shopify
    # Everything the "Orders" section of a conversation shows, in one answer.
    # The state says what the section is: not_connected, broken, unavailable
    # (the store did not answer), refused (the store does not give the app its
    # orders or customers), limited, no_identifier, none, ambiguous or matched.
    class Panel
      def initialize(account:, conversation:, account_user:)
        @account = account
        @conversation = conversation
        @account_user = account_user
        @record = ShopifyConnection.find_by(account_id: account.id)
      end

      # With `after`, a further page of orders: what the first read settled
      # and refreshed is not read again.
      def as_json(after: nil)
        base = { viewer: viewer, connection: connection, can: can }
        return base.merge(state: 'not_connected') unless @record
        return base.merge(state: 'broken') if @record.broken?
        return base.merge(body(after)) if after

        OrderActionRunner.new(account: @account, account_user: @account_user, conversation: @conversation, connection: @record).settle_open!
        base.merge(body(after)).merge(marked_order).merge(open_actions)
      rescue Error::ConnectionBroken, Error::Unauthorized
        base.merge(connection: connection, state: 'broken')
      rescue Error::QueryError => e
        # Shopify refuses orders and customers to an app with no distribution
        # method, but only once the store has some: a store that was empty when
        # it was connected starts refusing later.
        base.merge(state: e.access_denied? ? 'refused' : 'unavailable', reason: 'query_error')
      rescue Error => e
        base.merge(state: 'unavailable', reason: e.class.name.demodulize.underscore)
      end

      def viewer
        { administrator: @account_user&.administrator? || false, can_act_on_orders: OrderRole.allows?(@account_user) }
      end

      # What this member may change from the panel, decided by the role and the
      # scopes of the app. The server checks again on every request.
      def can
        allowed = @record.present? && @record.working? && OrderRole.allows?(@account_user)
        {
          order_marks: allowed && @record.unavailable_reason('order_tags').nil?,
          customer_marks: allowed && @record.unavailable_reason('customer_tags').nil?
        }
      end

      def connection
        return { connected: false, encryption_configured: Chatwoot.encryption_configured? } unless @record

        {
          connected: true, status: @record.status, shop_name: @record.shop_name, shop_domain: @record.shop_domain,
          shop_currency: @record.shop_currency, customer_data: @record.customer_data_mode, actions: @record.actions_report
        }
      end

      # With the values of the reply variables, for the dashboard's editor.
      def present_order(node)
        OrderPresenter.new(node, shop_domain: @record.shop_domain).as_json.merge(variables: OrderVariables.new(node).to_h)
      end

      private

      def reader
        @reader ||= OrderReader.new(@record)
      end

      # The order this conversation is about, read again so that its attributes
      # on the conversation stay current. Cleared when the store no longer has it.
      def marked_order
        marker = ConversationOrder.new(@conversation, connection: @record)
        return { marked_order: nil } if marker.marked_id.blank?

        node = reader.order(marker.marked_id)
        if node.nil?
          marker.clear!
          return { marked_order: nil }
        end
        marker.mark!(node)
        { marked_order: present_order(node) }
      end

      # Actions of this conversation that are not settled yet: a cancellation
      # the store is still working on, or an attempt whose answer was lost.
      def open_actions
        { open_actions: OrderAction.unsettled.where(account_id: @account.id, conversation_id: @conversation.id).order(:id).map(&:as_json) }
      end

      def body(after)
        match = CustomerMatcher.new(reader, @conversation.contact, limited: @record.customer_data_limited?).call
        return { state: match.state, candidates: match.candidates } unless match.state == 'matched'

        customer = reader.customer_with_orders(match.customer_id, after: after)
        # A remembered customer may have been deleted or merged at the store.
        return { state: 'none', candidates: [], stale_choice: true } unless customer

        # The facts automation rules use follow what the store says now.
        CustomerFacts.new(@conversation).write!(CustomerFacts.of(customer))
        orders = customer['orders'] || {}
        {
          state: 'matched', candidates: [],
          customer: CustomerMatcher.candidate(customer).merge(tags: Array(customer['tags']), note: customer['note'].presence),
          orders: Array(orders['nodes']).map { |node| present_order(node) },
          page: { has_more: orders.dig('pageInfo', 'hasNextPage') || false, cursor: orders.dig('pageInfo', 'endCursor') }
        }
      end
    end
  end
end
