# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Refunds an order: everything that remains, chosen items (with or
      # without shipping), the shipping alone, or an amount. The store
      # proposes through which payments the money goes back; we never invent
      # a payment. The action id is the idempotency key, so one confirmation
      # is at most one refund.
      #
      # Restocking, as a live store takes it: every restocked line names a
      # location, also in a store that has one; units that have not shipped go
      # back as a cancellation and units that have shipped as a return, and a
      # unit sent as the wrong kind is silently not restocked. So a line is
      # sent as several entries. The agent does not choose where: shipped
      # units go back to the location the store proposes (the one they were
      # shipped from), units that have not shipped to the location their
      # fulfilment order keeps them at. A unit the store names no location for
      # is refunded without restocking. Reading these needs two scopes;
      # without either nothing is restocked.
      class Refund < Base
        MODES = %w[full items shipping amount].freeze
        RECORDED = %w[mode amount items shipping restock notify].freeze
        RESTOCK_SCOPES = %w[read_locations read_merchant_managed_fulfillment_orders].freeze

        # What the confirmation shows: the amount, its currency and where the money goes.
        def preview
          plan = build_plan
          {
            amount: plan[:total].to_s('F'), currency: currency, maximum: maximum.to_s('F'),
            destinations: plan[:transactions].map { |transaction| { gateway: transaction[:label], amount: transaction[:amount] } },
            notify: params['notify'] == true
          }.merge(restock_preview(plan))
        end

        # The refund is worked out once, from the order as it is then, and kept
        # in the record before the store is asked. A repeated request sends the
        # very same refund under the same key, which the store answers with the
        # refund it already made; worked out again from an order that has been
        # refunded meanwhile, it would be refused as nothing left to refund.
        def call
          prepare unless @record.progress.key?('input')
          sent = @record.progress
          answer = @store.query(:refund_create, { key: @record.action_id, input: JSON.parse(sent['input']) })['refundCreate']
          user_errors!(answer['userErrors'])
          refunded = answer.dig('refund', 'totalRefundedSet', 'shopMoney') || {}
          remember!(refund_id: answer.dig('refund', 'id'), refunded: "#{refunded['amount'] || sent['total']} #{refunded['currencyCode'] || sent['currency']}")
          :accepted
        end

        # After a lost answer, only a refund carrying the marker sent with
        # this attempt can settle it. Amount and time alone cannot distinguish
        # it from another refund. Nothing is sent to the store.
        def resolve
          # The attempt ended before the store was asked for the refund.
          raise Refused, 'store_unreachable' unless @record.progress.key?('input')
          return :accepted if @record.progress['refund_id']

          order = @store.query(:order_details_limited, { id: @record.order_id })['order']
          refund = order && matching_refund(order)
          return unless refund

          money = refund.dig('totalRefundedSet', 'shopMoney') || {}
          remember!(refund_id: refund['id'], refunded: "#{money['amount']} #{money['currencyCode']}")
          :accepted
        end

        private

        def prepare
          plan = build_plan
          # Kept as text, so that it is sent again byte for byte.
          remember!(input: input_for(plan).to_json, total: plan[:total].to_s('F'), currency: currency, restocked_at: restocked_at(plan))
        end

        def matching_refund(order)
          # Older attempts did not send a marker: keep those unknown rather
          # than attributing an unrelated refund to them.
          marker = JSON.parse(@record.progress['input'])['note']
          return if marker.blank?

          taken = OrderAction.where(account_id: @record.account_id, order_id: @record.order_id, action: 'refund').where.not(id: @record.id)
                             .filter_map { |other| other.progress['refund_id'] }
          matches = Array(order['refunds']).select do |refund|
            money = refund.dig('totalRefundedSet', 'shopMoney') || {}
            refund['id'].present? && !taken.include?(refund['id']) && refund['note'] == marker &&
              money['amount'].to_d == @record.progress['total'].to_d && money['currencyCode'] == @record.progress['currency']
          end
          matches.one? ? matches.first : nil
        end

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
        # shipped are counted first, each kind at its location.
        def entries_for(line, quantity)
          base = { lineItemId: line['id'] }
          return [base.merge(quantity: quantity, restockType: 'NO_RESTOCK')] unless params['restock'] == true
          return [base.merge(quantity: quantity, restockType: 'NO_RESTOCK', left_out: true)] if missing_restock_scopes.any?

          unshipped = [line['unfulfilledQuantity'].to_i, quantity].min
          cancelled(line['id'], unshipped) + [base.merge(quantity: quantity - unshipped, restockType: 'RETURN', restock: true)].select { |entry| entry[:quantity].positive? }
        end

        def missing_restock_scopes
          RESTOCK_SCOPES - @store.record.scopes
        end

        # Units of a line that have not shipped, spread over the locations
        # that keep them, in the order the store lists its fulfilment orders.
        def cancelled(line_id, units)
          # Nothing waits to ship: the fulfilment orders are not asked for.
          return [] unless units.positive?

          entries = []
          (assigned_locations[line_id] || []).each do |place|
            taken = [units, place[:left]].min
            next unless taken.positive?

            place[:left] -= taken
            units -= taken
            entries << { lineItemId: line_id, quantity: taken, restockType: 'CANCEL', restock: true, locationId: place[:id], location: place[:name] }
          end
          entries << { lineItemId: line_id, quantity: units, restockType: 'NO_RESTOCK', unplaced: true } if units.positive?
          entries
        end

        # line item id => [{ id:, name:, left: }], from the fulfilment orders.
        def assigned_locations
          @assigned_locations ||= begin
            orders = Array(@store.query(:refund_assigned_locations, { id: @record.order_id }).dig('order', 'fulfillmentOrders', 'nodes'))
            orders.each_with_object({}) do |order, found|
              location = order['assignedLocation'] || {}
              next unless location.dig('location', 'id')

              Array(order.dig('lineItems', 'nodes')).each do |line|
                next unless line['remainingQuantity'].to_i.positive?

                (found[line.dig('lineItem', 'id')] ||= []) << { id: location.dig('location', 'id'), name: location['name'], left: line['remainingQuantity'].to_i }
              end
            end
          end
        end

        # Gives every returned entry the location the store proposes for it.
        def placed(items)
          returned = items.select { |item| item[:restock] && item[:restockType] == 'RETURN' }
          return items if returned.empty?

          proposed = return_locations(returned)
          items.map do |item|
            next item unless returned.include?(item)

            location = proposed[item[:lineItemId]]
            next item.except(:restock).merge(restockType: 'NO_RESTOCK', unplaced: true) unless location

            item.merge(locationId: location['id'], location: location['name'])
          end
        end

        # line item id => the location the store would return it to.
        def return_locations(entries)
          variables = { id: @record.order_id, refundLineItems: entries.map { |entry| entry.slice(:lineItemId, :quantity, :restockType) } }
          suggested = @store.query(:refund_return_locations, variables).dig('order', 'suggestedRefund', 'refundLineItems')
          Array(suggested).select { |item| item['restockType'] == 'RETURN' && item['location'] }.to_h { |item| [item.dig('lineItem', 'id'), item['location']] }
        end

        def restocked_at(plan)
          plan[:items].filter_map { |item| item[:location] }.uniq
        end

        # What the confirmation says about stock: how many lines go back and
        # where, how many stay out for want of a scope, and how many because
        # the store names no location for them.
        def restock_preview(plan)
          lines = ->(mark) { plan[:items].select { |item| item[mark] }.pluck(:lineItemId).uniq.size }
          {
            restocked_items: lines.call(:restock), restock_locations: restocked_at(plan),
            left_out_items: lines.call(:left_out), missing_scopes: (lines.call(:left_out).positive? ? missing_restock_scopes : []),
            unplaced_items: lines.call(:unplaced)
          }
        end

        def build_plan
          amount = requested_amount if mode == 'amount'
          wanted = requested_items if mode == 'items'
          # The money does not depend on restocking: the store is asked without it.
          asked = wanted&.map { |item| { lineItemId: item[:line]['id'], quantity: item[:quantity], restockType: 'NO_RESTOCK' } }
          items = wanted&.flat_map { |item| entries_for(item[:line], item[:quantity]) }
          variables = { id: @record.order_id, refundLineItems: asked,
                        refundShipping: %w[items shipping].include?(mode) ? refunds_shipping? : nil, suggestFullRefund: %w[full amount].include?(mode) }
          suggestion = @store.query(:refund_suggestion, variables).dig('order', 'suggestedRefund') or raise Refused, 'nothing_to_refund'
          shipping_left = suggestion.dig('shipping', 'maximumRefundableSet', 'shopMoney', 'amount').to_d.positive?
          raise Refused, 'no_shipping_to_refund' if mode == 'shipping' && !shipping_left

          transactions = transactions_for(suggestion, amount)
          raise Refused, 'nothing_to_refund' if transactions.empty?

          {
            items: placed(items || (mode == 'full' ? suggested_items(suggestion) : [])),
            shipping: refunds_shipping? && shipping_left,
            transactions: transactions, total: transactions.sum { |transaction| BigDecimal(transaction[:amount]) }
          }
        end

        def refunds_shipping?
          mode == 'full' || mode == 'shipping' || (mode == 'items' && params['shipping'] == true)
        end

        # Everything the store would refund, line by line. The store may list
        # a line twice (its shipped and its unshipped units): they are summed.
        def suggested_items(suggestion)
          lines = Array(@order.dig('lineItems', 'nodes')).index_by { |line| line['id'] }
          wanted = Array(suggestion['refundLineItems']).each_with_object(Hash.new(0)) { |item, sums| sums[item.dig('lineItem', 'id')] += item['quantity'].to_i }
          wanted.flat_map { |id, quantity| entries_for(lines[id] || { 'id' => id }, quantity) }
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
            note: "Inclamo refund #{@record.action_id}",
            refundLineItems: plan[:items].map { |item| item.slice(:lineItemId, :quantity, :restockType, :locationId).compact }.presence,
            shipping: (plan[:shipping] ? { fullRefund: true } : nil),
            transactions: plan[:transactions].map { |transaction| transaction.slice(:parentId, :gateway, :amount).merge(orderId: @record.order_id, kind: 'REFUND') }
          }.compact
        end
      end
    end
  end
end
