# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Duplicates an order as a replacement that costs the customer nothing.
      # Three steps at the store: a draft copied from the order, the draft
      # reduced to the items the agent kept with a full discount and free
      # shipping, the draft completed into an order. Each finished step is
      # remembered, so a repeated request continues instead of starting again,
      # and a failure after the first step removes the draft.
      class Replacement < Base
        RECORDED = %w[items].freeze
        TAG = 'replacement'

        def initialize(shop_domain:, **rest)
          super(**rest)
          @shop_domain = shop_domain
        end

        def call
          return :accepted if @record.progress['new_order_id']
          return finish_from_store if @record.progress['draft_id'] && completed_at_store?

          lines = kept_lines # validated before anything is created
          create_draft unless @record.progress['draft_id']
          begin
            update_draft(lines) unless @record.progress['updated']
            complete_draft
          rescue Refused => e
            raise Refused.new(e.code, [e.message, cleanup_message].compact.join(' '))
          end
          :accepted
        end

        private

        def draft_id
          @record.progress['draft_id']
        end

        # The original order's lines the agent kept, with the quantity for each.
        def kept_lines
          originals = Array(@order.dig('lineItems', 'nodes'))
          wanted = Array(params['items']).map { |item| item.to_h.stringify_keys }
          wanted = originals.map { |line| { 'line_item_id' => line['id'], 'quantity' => line['quantity'] } } if wanted.empty?
          by_id = originals.index_by { |line| line['id'] }
          kept = wanted.map do |item|
            line = by_id[item['line_item_id']] or raise Refused, 'unknown_item'
            quantity = item['quantity'].to_i
            raise Refused, 'invalid_quantity' unless quantity.between?(1, line['quantity'].to_i)

            [line, quantity]
          end
          raise Refused, 'no_items' if kept.empty?

          kept
        end

        def create_draft
          answer = @store.query(:replacement_draft_create, { orderId: @record.order_id })['draftOrderCreateFromOrder']
          user_errors!(answer['userErrors'])
          draft = answer['draftOrder'] or raise Refused, 'store_refused'
          remember!(draft_id: draft['id'], draft_name: draft['name'],
                    draft_lines: Array(draft.dig('lineItems', 'nodes')).map { |line| { 'variant_id' => line.dig('variant', 'id'), 'title' => line['title'] } })
        end

        # The variant of an original line, taken from the draft the store made
        # of the order: same position, same title. The order itself is read
        # without variants, so that the panel needs no product scope.
        def variant_for(line)
          originals = Array(@order.dig('lineItems', 'nodes'))
          drafted = Array(@record.progress['draft_lines'])
          at = originals.index { |original| original['id'] == line['id'] }
          match = drafted[at] if at && drafted[at] && drafted[at]['title'] == line['title']
          match ||= drafted.find { |candidate| candidate['title'] == line['title'] }
          match && match['variant_id']
        end

        def update_draft(lines)
          items = lines.map do |line, quantity|
            variant = variant_for(line)
            if variant
              { variantId: variant, quantity: quantity }
            else
              price = line.dig('originalUnitPriceSet', 'shopMoney') || {}
              { title: line['title'], quantity: quantity, originalUnitPriceWithCurrency: { amount: price['amount'], currencyCode: price['currencyCode'] } }
            end
          end
          input = {
            lineItems: items,
            appliedDiscount: { valueType: 'PERCENTAGE', value: 100, title: 'Replacement' },
            shippingLine: { title: 'Replacement shipping', priceWithCurrency: { amount: '0', currencyCode: @order['currencyCode'] } },
            tags: [TAG], note: "Replacement for order #{@order['name']}"
          }
          answer = @store.query(:replacement_draft_update, { id: draft_id, input: input })['draftOrderUpdate']
          user_errors!(answer['userErrors'])
          total = answer.dig('draftOrder', 'totalPriceSet', 'shopMoney', 'amount').to_d
          # The customer must be charged nothing; anything else is not completed.
          raise Refused.new('not_free', "the replacement would cost #{total.to_s('F')} #{@order['currencyCode']}") if total.positive?

          remember!(updated: true)
        end

        def complete_draft
          answer = @store.query(:replacement_draft_complete, { id: draft_id })['draftOrderComplete']
          user_errors!(answer['userErrors'])
          order = answer.dig('draftOrder', 'order') or raise Refused, 'store_refused'
          remember!(new_order_id: order['id'], new_order_number: order['name'])
        end

        # After a lost answer: did the draft become an order anyway?
        def completed_at_store?
          draft = @store.query(:replacement_draft, { id: draft_id })['draftOrder']
          @completed = draft && draft['order']
          @completed.present?
        end

        def finish_from_store
          remember!(new_order_id: @completed['id'], new_order_number: @completed['name'])
          :accepted
        end

        # Removes the unfinished draft; when that fails, names it so that it is not left unnoticed.
        def cleanup_message
          answer = @store.query(:replacement_draft_delete, { id: draft_id })['draftOrderDelete']
          return if Array(answer['userErrors']).empty?

          left_behind
        rescue Error
          left_behind
        end

        def left_behind
          number = draft_id.to_s.split('/').last
          "The unfinished draft #{@record.progress['draft_name']} could not be removed: " \
            "https://admin.shopify.com/store/#{@shop_domain.delete_suffix('.myshopify.com')}/draft_orders/#{number}"
        end
      end
    end
  end
end
