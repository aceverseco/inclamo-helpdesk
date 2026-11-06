# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Refunds an order: everything that remains, chosen items (with or
      # without shipping), or an amount. The store proposes through which
      # payments the money goes back; we never invent a payment. The action id
      # is the idempotency key, so one confirmation is at most one refund.
      #
      # Restocking, as a live store takes it: every restocked line names a
      # location, also in a store that has one; units that have not shipped go
      # back as a cancellation and units that have shipped as a return, and a
      # unit sent as the wrong kind is silently not restocked. So a line is
      # sent as up to two entries, both at the store's only location or the one
      # the agent chose. Locations can only be read with read_locations;
      # without it nothing is restocked.
      class Refund < Base
        MODES = %w[full items amount].freeze
        RECORDED = %w[mode amount items shipping restock notify location_id].freeze
        LOCATIONS_SCOPE = 'read_locations'

        # What the confirmation shows: the amount, its currency and where the money goes.
        def preview
          plan = build_plan
          {
            amount: plan[:total].to_s('F'), currency: currency, maximum: maximum.to_s('F'),
            destinations: plan[:transactions].map { |transaction| { gateway: transaction[:label], amount: transaction[:amount] } },
            notify: params['notify'] == true
          }.merge(restock_preview(plan))
        end

        def call
          plan = build_plan
          raise Refused, 'location_needed' if plan[:items].any? { |item| item[:restock] && item[:locationId].nil? }

          answer = @store.query(:refund_create, { key: @record.action_id, input: input_for(plan) })['refundCreate']
          user_errors!(answer['userErrors'])
          refunded = answer.dig('refund', 'totalRefundedSet', 'shopMoney') || {}
          remember!(refund_id: answer.dig('refund', 'id'), refunded: "#{refunded['amount'] || plan[:total].to_s('F')} #{refunded['currencyCode'] || currency}")
          :accepted
        end

        private

        def mode
          MODES.include?(params['mode']) ? params['mode'] : (raise Refused, 'invalid_mode')
        end

        def currency
          @order['currencyCode']
        end

        def maximum
          OrderPresenter.new(@order, shop_domain: '').refundable_amount
        end

        def requested_amount
          amount = BigDecimal(params['amount'].to_s)
          raise Refused, 'invalid_amount' unless amount.positive?
          # Refused here, before the store is asked for anything.
          raise Refused, 'above_refundable' if amount > maximum

          amount
        rescue ArgumentError, TypeError
          raise Refused, 'invalid_amount'
        end

        # The lines the agent chose, each with its quantity.
        def requested_items
          wanted = Array(params['items']).map { |item| item.to_h.stringify_keys }
          raise Refused, 'no_items' if wanted.empty?

          lines = Array(@order.dig('lineItems', 'nodes')).index_by { |line| line['id'] }
          wanted.map do |item|
            line = lines[item['line_item_id']] or raise Refused, 'unknown_item'
            quantity = item['quantity'].to_i
            raise Refused, 'invalid_quantity' unless quantity.between?(1, line['refundableQuantity'].to_i)

            { line: line, quantity: quantity }
          end
        end

        # One refunded line as the entries the store takes: units that have not
        # shipped are counted first.
        def entries_for(line, quantity)
          base = { lineItemId: line['id'] }
          return [base.merge(quantity: quantity, restockType: 'NO_RESTOCK')] unless params['restock'] == true
          return [base.merge(quantity: quantity, restockType: 'NO_RESTOCK', left_out: true)] unless locations_readable?

          location = restock_location&.dig('id')
          unshipped = [line['unfulfilledQuantity'].to_i, quantity].min
          [['CANCEL', unshipped], ['RETURN', quantity - unshipped]].filter_map do |kind, units|
            base.merge(quantity: units, restockType: kind, locationId: location, restock: true) if units.positive?
          end
        end

        def locations_readable?
          @store.record.scopes.include?(LOCATIONS_SCOPE)
        end

        def locations
          @locations ||= Array(@store.query(:locations).dig('locations', 'nodes'))
        end

        # The location the agent chose, or the store's only one. Nil when the
        # store has several and none is chosen yet: the confirmation asks.
        def restock_location
          wanted = params['location_id'].presence
          return locations.find { |location| location['id'] == wanted } || (raise Refused, 'unknown_location') if wanted

          locations.first if locations.size == 1
        end

        # What the confirmation says about stock: how many lines go back and
        # where, or how many stay out for want of the scope.
        def restock_preview(plan)
          restocked = plan[:items].select { |item| item[:restock] }.pluck(:lineItemId).uniq.size
          left_out = plan[:items].count { |item| item[:left_out] }
          {
            restocked_items: restocked, locations: restocked.positive? ? locations.map { |location| location.slice('id', 'name') } : [],
            location_id: (restock_location&.dig('id') if restocked.positive?),
            left_out_items: left_out, missing_scope: (LOCATIONS_SCOPE if left_out.positive?)
          }
        end

        def build_plan
          amount = requested_amount if mode == 'amount'
          wanted = requested_items if mode == 'items'
          # The money does not depend on restocking: the store is asked without it.
          asked = wanted&.map { |item| { lineItemId: item[:line]['id'], quantity: item[:quantity], restockType: 'NO_RESTOCK' } }
          items = wanted&.flat_map { |item| entries_for(item[:line], item[:quantity]) }
          variables = { id: @record.order_id, refundLineItems: asked,
                        refundShipping: mode == 'items' ? params['shipping'] == true : nil, suggestFullRefund: mode != 'items' }
          suggestion = @store.query(:refund_suggestion, variables).dig('order', 'suggestedRefund') or raise Refused, 'nothing_to_refund'
          transactions = transactions_for(suggestion, amount)
          raise Refused, 'nothing_to_refund' if transactions.empty?

          {
            items: items || (mode == 'full' ? suggested_items(suggestion) : []),
            shipping: (mode == 'full' || (mode == 'items' && params['shipping'] == true)) && suggestion.dig('shipping', 'maximumRefundableSet', 'shopMoney', 'amount').to_d.positive?,
            transactions: transactions, total: transactions.sum { |transaction| BigDecimal(transaction[:amount]) }
          }
        end

        def suggested_items(suggestion)
          lines = Array(@order.dig('lineItems', 'nodes')).index_by { |line| line['id'] }
          Array(suggestion['refundLineItems']).flat_map do |item|
            entries_for(lines[item.dig('lineItem', 'id')] || { 'id' => item.dig('lineItem', 'id') }, item['quantity'].to_i)
          end
        end

        # The store's proposal, or for a custom amount that amount spread over
        # the payments in the order the store proposes them.
        def transactions_for(suggestion, amount)
          left = amount
          Array(suggestion['suggestedTransactions']).filter_map do |transaction|
            limit = BigDecimal(transaction.dig('maximumRefundableSet', 'shopMoney', 'amount') || '0')
            value = amount ? [left, limit].min : BigDecimal(transaction.dig('amountSet', 'shopMoney', 'amount') || '0')
            left -= value if amount
            next unless value.positive?

            { parentId: transaction.dig('parentTransaction', 'id'), gateway: transaction['gateway'], amount: value.to_s('F'),
              label: transaction['formattedGateway'] || transaction['gateway'] }
          end
        end

        def input_for(plan)
          {
            orderId: @record.order_id, notify: params['notify'] == true,
            refundLineItems: plan[:items].map { |item| item.slice(:lineItemId, :quantity, :restockType, :locationId).compact }.presence,
            shipping: (plan[:shipping] ? { fullRefund: true } : nil),
            transactions: plan[:transactions].map { |transaction| transaction.slice(:parentId, :gateway, :amount).merge(orderId: @record.order_id, kind: 'REFUND') }
          }.compact
        end
      end
    end
  end
end
