# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Refunds an order: everything that remains, chosen items (with or
      # without shipping), or an amount. The store proposes through which
      # payments the money goes back; we never invent a payment. The action id
      # is the idempotency key, so one confirmation is at most one refund.
      class Refund < Base
        MODES = %w[full items amount].freeze
        RECORDED = %w[mode amount items shipping restock notify].freeze

        # What the confirmation shows: the amount, its currency and where the money goes.
        def preview
          plan = build_plan
          {
            amount: plan[:total].to_s('F'), currency: currency, maximum: maximum.to_s('F'),
            destinations: plan[:transactions].map { |transaction| { gateway: transaction[:label], amount: transaction[:amount] } },
            restocked_items: plan[:items].count { |item| item[:restockType] != 'NO_RESTOCK' }, notify: params['notify'] == true
          }
        end

        def call
          plan = build_plan
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

        def requested_items
          wanted = Array(params['items']).map { |item| item.to_h.stringify_keys }
          raise Refused, 'no_items' if wanted.empty?

          lines = Array(@order.dig('lineItems', 'nodes')).index_by { |line| line['id'] }
          wanted.map do |item|
            line = lines[item['line_item_id']] or raise Refused, 'unknown_item'
            quantity = item['quantity'].to_i
            raise Refused, 'invalid_quantity' unless quantity.between?(1, line['refundableQuantity'].to_i)

            restock = params['restock'] == true && line['unfulfilledQuantity'].to_i >= quantity
            { lineItemId: line['id'], quantity: quantity, restockType: restock ? 'CANCEL' : 'NO_RESTOCK' }
          end
        end

        def build_plan
          amount = requested_amount if mode == 'amount'
          items = requested_items if mode == 'items'
          variables = { id: @record.order_id, refundLineItems: items&.map { |item| item.slice(:lineItemId, :quantity, :restockType) },
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

        # Items go back into stock only where the store needs no location for
        # it: items that have not shipped. Returning shipped items to a
        # location is done in the store's admin.
        def suggested_items(suggestion)
          lines = Array(@order.dig('lineItems', 'nodes')).index_by { |line| line['id'] }
          Array(suggestion['refundLineItems']).map do |item|
            line = lines[item.dig('lineItem', 'id')] || {}
            restock = params['restock'] == true && line['unfulfilledQuantity'].to_i >= item['quantity'].to_i
            { lineItemId: item.dig('lineItem', 'id'), quantity: item['quantity'], restockType: restock ? 'CANCEL' : 'NO_RESTOCK' }
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
            refundLineItems: plan[:items].presence,
            shipping: (plan[:shipping] ? { fullRefund: true } : nil),
            transactions: plan[:transactions].map { |transaction| transaction.slice(:parentId, :gateway, :amount).merge(orderId: @record.order_id, kind: 'REFUND') }
          }.compact
        end
      end
    end
  end
end
