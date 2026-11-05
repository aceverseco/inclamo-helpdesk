# frozen_string_literal: true

module Inclamo
  module Shopify
    # Everything the "Orders" section of a conversation shows, in one answer.
    # The state says what the section is: not_connected, broken, unavailable
    # (the store did not answer), limited, no_identifier, none, ambiguous or
    # matched.
    class Panel
      def initialize(account:, conversation:, account_user:)
        @account = account
        @conversation = conversation
        @account_user = account_user
        @record = ShopifyConnection.find_by(account_id: account.id)
      end

      def as_json(after: nil)
        base = { viewer: viewer, connection: connection }
        return base.merge(state: 'not_connected') unless @record
        return base.merge(state: 'broken') if @record.broken?

        base.merge(body(after))
      rescue Error::ConnectionBroken, Error::Unauthorized
        base.merge(connection: connection, state: 'broken')
      rescue Error => e
        base.merge(state: 'unavailable', reason: e.class.name.demodulize.underscore)
      end

      def viewer
        { administrator: @account_user&.administrator? || false, can_act_on_orders: OrderRole.allows?(@account_user) }
      end

      def connection
        return { connected: false, encryption_configured: Chatwoot.encryption_configured? } unless @record

        @record.reload if @record.persisted?
        {
          connected: true, status: @record.status, shop_name: @record.shop_name, shop_domain: @record.shop_domain,
          shop_currency: @record.shop_currency, customer_data: @record.customer_data_mode, actions: @record.actions_report
        }
      end

      def present_order(node)
        OrderPresenter.new(node, shop_domain: @record.shop_domain).as_json
      end

      private

      def reader
        @reader ||= OrderReader.new(@record)
      end

      def body(after)
        match = CustomerMatcher.new(reader, @conversation.contact, limited: @record.customer_data_limited?).call
        return { state: match.state, candidates: match.candidates } unless match.state == 'matched'

        customer = reader.customer_with_orders(match.customer_id, after: after)
        # A remembered customer may have been deleted or merged at the store.
        return { state: 'none', candidates: [], stale_choice: true } unless customer

        orders = customer['orders'] || {}
        {
          state: 'matched', candidates: [],
          customer: CustomerMatcher.candidate(customer),
          orders: Array(orders['nodes']).map { |node| present_order(node) },
          page: { has_more: orders.dig('pageInfo', 'hasNextPage') || false, cursor: orders.dig('pageInfo', 'endCursor') }
        }
      end
    end
  end
end
