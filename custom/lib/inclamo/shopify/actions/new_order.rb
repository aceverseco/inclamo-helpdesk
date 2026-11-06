# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Builds an order for the customer of a conversation and hands them its
      # payment link. At the store the order is a draft until the customer pays
      # through the invoice link: nothing here marks it paid or takes a payment.
      #
      # It is not about an existing order. The customer is the one matched to
      # the conversation, given when the action starts; their id is remembered
      # so that an attempt whose answer was lost can be settled later. The note
      # for the merchant is not recorded, like an address.
      #
      # The store does not deduplicate draft creation, so every draft carries
      # the action id in a metafield, and only the request that started the
      # action (the one given the customer) ever creates a draft. Settling an
      # earlier attempt (a repeated request, a panel read) only looks for its
      # draft by the marker, once the store's search has caught up
      # (LOOK_AFTER): found, it is finished; not found, nothing was created.
      class NewOrder < Base
        RECORDED = %w[lines discount shipping delivery].freeze
        TAG = 'inclamo-helpdesk'
        MARKER = { namespace: 'inclamo', key: 'action_id' }.freeze
        DELIVERIES = %w[email reply].freeze
        DISCOUNT_TYPES = { 'percentage' => 'PERCENTAGE', 'amount' => 'FIXED_AMOUNT' }.freeze
        MAX_LINES = 50
        MAX_QUANTITY = 999
        NOTE_LENGTH = 1000
        AWAITING = 5
        LOOK_AFTER = 30.seconds
        VARIANT_ID = %r{\Agid://shopify/ProductVariant/\d+\z}
        AMOUNT = /\A\d{1,9}(\.\d{1,2})?\z/

        def initialize(customer: nil, note: nil, **rest)
          super(order: nil, **rest.except(:order))
          @customer = customer
          @note = note.to_s.strip.first(NOTE_LENGTH).presence
        end

        # The query for one customer's drafts made from the helpdesk; `open`
        # leaves out the ones already paid.
        def self.drafts_query(customer_id, open: true)
          query = "customer_id:#{customer_id.to_s.split('/').last} tag:#{TAG}"
          open ? "#{query} (status:open OR status:invoice_sent)" : query
        end

        # One order awaiting payment, as the panel shows it.
        def self.present_awaiting(node, shop_domain:)
          {
            id: node['id'], number: node['name'], status: node['status'].to_s.downcase, created_at: node['createdAt'],
            total: money(node['totalPriceSet']), invoice_url: node['invoiceUrl'], invoice_sent: node['invoiceSentAt'].present?,
            admin_url: "https://admin.shopify.com/store/#{shop_domain.delete_suffix('.myshopify.com')}/draft_orders/#{node['legacyResourceId']}",
            items: Array(node.dig('lineItems', 'nodes')).map { |line| { title: line['name'], quantity: line['quantity'] } }
          }
        end

        # The store's calculation, as the summary shows it.
        def self.present_calculation(calculated)
          {
            currency: calculated['currencyCode'], taxes_included: calculated['taxesIncluded'],
            lines: Array(calculated['lineItems']).map do |line|
              { variant_id: line.dig('variant', 'id'), title: line['name'], sku: line['sku'], quantity: line['quantity'],
                unit_price: money(line['originalUnitPriceSet']), total: money(line['discountedTotalSet']) }
            end,
            subtotal: money(calculated['lineItemsSubtotalPrice']), discount: money(calculated['totalDiscountsSet']),
            shipping: money(calculated['totalShippingPriceSet']), tax: money(calculated['totalTaxSet']),
            total: money(calculated['totalPriceSet']), warnings: Array(calculated['warnings']).pluck('message')
          }
        end

        # The items of an existing order as lines of a new one ("order again").
        # Items whose product is gone or no longer sold are named, not added.
        def self.prefill(order, currency:)
          lines = []
          skipped = []
          Array(order.dig('lineItems', 'nodes')).each do |line|
            variant = line['variant']
            product = variant && variant['product']
            if product.nil? || product['status'] != 'ACTIVE'
              skipped << { title: line['name'], quantity: line['quantity'] }
              next
            end
            lines << { product: ProductSearch.present_product(product, currency: currency), variant: ProductSearch.present_variant(variant, currency: currency),
                       quantity: line['quantity'] }
          end
          { order_number: order['name'], lines: lines, skipped: skipped }
        end

        def self.money(set)
          shop = set && set['shopMoney']
          shop && { amount: shop['amount'], currency: shop['currencyCode'] }
        end

        # Why this order cannot be made, decided before the store is asked; nil
        # when it can. A preview does not need to know how the link is delivered.
        def refusal(preview: false)
          return 'no_customer' unless @customer
          return 'no_items' if lines.empty?
          return 'too_many_items' if lines.size > MAX_LINES
          return 'invalid_item' unless lines.all? { |line| line['variant_id'].to_s.match?(VARIANT_ID) }
          return 'invalid_quantity' unless lines.all? { |line| line['quantity'].between?(1, MAX_QUANTITY) }
          return 'invalid_discount' if discount_input == :invalid
          return 'invalid_shipping' if shipping_input == :invalid
          return if preview
          return 'invalid_delivery' unless DELIVERIES.include?(delivery)

          'no_email' if delivery == 'email' && @customer.dig('defaultEmailAddress', 'emailAddress').blank?
        end

        # The store's calculation of this order; nothing is created.
        def preview
          answer = @store.query(:new_order_calculate, { input: input })['draftOrderCalculate']
          user_errors!(answer['userErrors'])
          calculated = answer['calculatedDraftOrder'] or raise Refused, 'store_refused'
          self.class.present_calculation(calculated)
        end

        def call
          unless draft_id
            if @customer
              create_draft
            else
              return :unknown if @record.created_at.present? && @record.created_at > LOOK_AFTER.ago

              (@record.progress['attempted'] && find_lost_draft) or raise Refused, 'not_created'
            end
          end
          deliver
          :accepted
        end

        private

        def draft_id
          @record.progress['draft_id']
        end

        def delivery
          params['delivery'].to_s
        end

        def customer_id
          @customer ? @customer['id'] : @record.progress['customer_id']
        end

        def currency
          @store.record.shop_currency
        end

        # The lines as recorded: one per variant, quantities of repeated variants added up.
        def lines
          @lines ||= Array(params['lines']).map { |line| line.to_h.stringify_keys }
                                           .group_by { |line| line['variant_id'].to_s }
                                           .map { |variant, same| { 'variant_id' => variant, 'quantity' => same.sum { |line| line['quantity'].to_i } } }
        end

        # One discount for the whole order, a percentage or an amount; nil for none.
        def discount_input
          discount = params['discount']
          return if discount.blank?

          discount = discount.to_h.stringify_keys
          type = DISCOUNT_TYPES[discount['type'].to_s]
          value = discount['value'].to_s
          return :invalid unless type && value.match?(AMOUNT) && value.to_d.positive?
          return :invalid if type == 'PERCENTAGE' && value.to_d > 100

          applied = { valueType: type, value: value.to_f, title: 'Discount' }
          applied[:amountWithCurrency] = { amount: value, currencyCode: currency } if type == 'FIXED_AMOUNT'
          applied
        end

        # A shipping charge of an amount; nil for none.
        def shipping_input
          amount = params['shipping'].to_s
          return if amount.blank?
          return :invalid unless amount.match?(AMOUNT)
          return if amount.to_d.zero?

          { title: 'Shipping', priceWithCurrency: { amount: amount, currencyCode: currency } }
        end

        def input
          {
            purchasingEntity: { customerId: customer_id }, useCustomerDefaultAddress: true,
            lineItems: lines.map { |line| { variantId: line['variant_id'], quantity: line['quantity'] } },
            appliedDiscount: discount_input, shippingLine: shipping_input
          }.compact
        end

        def create_draft
          # Written before the store is asked: a lost answer is then looked for, never made twice.
          remember!(attempted: true, customer_id: customer_id)
          full = input.merge(tags: [TAG], note: @note, metafields: [MARKER.merge(type: 'single_line_text_field', value: @record.action_id)]).compact
          answer = @store.query(:new_order_create, { input: full })['draftOrderCreate']
          user_errors!(answer['userErrors'])
          draft = answer['draftOrder'] or raise Refused, 'store_refused'
          remember_draft!(draft)
        end

        def remember_draft!(draft)
          remember!(draft_id: draft['id'], draft_name: draft['name'], draft_number: draft['legacyResourceId'],
                    total: self.class.money(draft['totalPriceSet']), invoice_url: draft['invoiceUrl'], delivery: delivery,
                    invoice_sent: draft['invoiceSentAt'].present?)
        end

        # The draft an earlier attempt made, by its marker among the customer's drafts.
        def find_lost_draft
          nodes = @store.query(:awaiting_payment, { query: self.class.drafts_query(customer_id, open: false), first: 10 }).dig('draftOrders', 'nodes')
          found = Array(nodes).find { |node| node.dig('marker', 'value') == @record.action_id }
          found && remember_draft!(found)
        end

        # The store emails its invoice when the agent chose that; otherwise the
        # dialog puts the link into the reply. A refused invoice removes the draft.
        def deliver
          return unless delivery == 'email'
          return if @record.progress['invoice_sent'] || invoice_sent_at_store?

          answer = @store.query(:new_order_invoice_send, { id: draft_id })['draftOrderInvoiceSend']
          begin
            user_errors!(answer['userErrors'])
          rescue Refused => e
            raise Refused.new(e.code, [e.message, cleanup_message].compact.join(' '))
          end
          remember!(invoice_sent: true)
        end

        # After a lost answer: did the invoice go out anyway?
        def invoice_sent_at_store?
          return false unless @record.progress['attempted'] && @record.outcome == 'unknown'

          draft = @store.query(:new_order_draft, { id: draft_id })['draftOrder']
          sent = draft && draft['invoiceSentAt'].present?
          remember!(invoice_sent: true) if sent
          sent
        end

        # Removes a draft whose invoice the store refused; when that fails, names it.
        def cleanup_message
          answer = @store.query(:replacement_draft_delete, { id: draft_id })['draftOrderDelete']
          if Array(answer['userErrors']).empty?
            remember!(draft_id: nil, removed: true)
            return
          end

          left_behind
        rescue Error
          left_behind
        end

        def left_behind
          "The draft #{@record.progress['draft_name']} could not be removed: " \
            "https://admin.shopify.com/store/#{@store.record.shop_domain.delete_suffix('.myshopify.com')}/draft_orders/#{@record.progress['draft_number']}"
        end
      end
    end
  end
end
