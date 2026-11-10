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
      # draft by the marker among every draft of the customer made around the
      # attempt, once the store's search has caught up (LOOK_AFTER): found, it
      # is finished; not found, nothing was created.
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
        AWAITING_STATUSES = %w[OPEN INVOICE_SENT].freeze
        LOOK_AFTER = 30.seconds
        # A lost draft is looked for among the customer's drafts made around
        # its record: the store's clock may differ from ours by this much.
        CLOCK_SKEW = 5.minutes
        LOOK_PAGE = 50
        LOOK_PAGES = 10
        VARIANT_ID = %r{\Agid://shopify/ProductVariant/\d+\z}
        AMOUNT = /\A\d{1,9}(\.\d{1,2})?\z/
        # Stands for a parameter of the wrong shape in the record; the refusal names it.
        INVALID = 'invalid'
        TEXT_LENGTH = 100

        def initialize(customer: nil, note: nil, **rest)
          super(order: nil, **rest.except(:order))
          @customer = customer
          @note = note.to_s.strip.first(NOTE_LENGTH).presence
        end

        # The customer is given only to the request that starts the action;
        # the note comes with the request and is not recorded.
        def self.context(extra:, **)
          { customer: extra[:customer], note: extra[:note] || extra['note'] }
        end

        # The draft, its total and how the payment link reached the customer; no customer data.
        def self.note_facts(record)
          total = record.progress['total'] || {}
          { draft_name: record.progress['draft_name'], total: [total['amount'], total['currency']].compact.join(' '),
            delivery: I18n.t("inclamo.order_actions.notes.details.#{delivered(record)}") }
        end

        # The dialog puts the link into the reply when its request is answered;
        # an attempt settled by reading the store answered no dialog.
        def self.delivered(record)
          return 'invoice_emailed' if record.progress['invoice_sent']
          return 'link_in_reply' if record.params['delivery'] == 'reply' && !record.progress['found_by_reading']

          'link_not_sent'
        end

        # The query for one customer's drafts made from the helpdesk; `open`
        # leaves out the ones already paid.
        def self.drafts_query(customer_id, open: true)
          query = "customer_id:#{customer_id.to_s.split('/').last} tag:#{TAG}"
          open ? "#{query} (status:open OR status:invoice_sent)" : query
        end

        # Drafts made for the customer from the helpdesk moments ago, which the
        # store's search may not show yet (it took 1-3 s on the test store;
        # LOOK_AFTER is the margin the lost-attempt lookup trusts too).
        def self.just_made(account_id, customer_id)
          OrderAction.where(account_id: account_id, action: 'new_order', outcome: 'accepted', completed_at: LOOK_AFTER.ago..)
                     .where("progress->>'customer_id' = ?", customer_id.to_s).filter_map { |record| record.progress['draft_id'] }
        end

        # One order awaiting payment, as the panel shows it.
        def self.present_awaiting(node, shop_domain:)
          {
            id: node['id'], number: node['name'], status: node['status'].to_s.downcase, created_at: node['createdAt'],
            total: money(node['totalPriceSet']), invoice_url: node['invoiceUrl'], invoice_sent: node['invoiceSentAt'].present?,
            admin_url: Shopify.admin_url(shop_domain, 'draft_orders', node['legacyResourceId']),
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

        # The items of an existing order as lines of a new one ("order again"),
        # one per variant, at their current quantity: units refunded or removed
        # since are left out. Items the catalogue search would not offer (the
        # product is gone, not active or a gift card, or the variant cannot be
        # sold) are named, not added.
        def self.prefill(order, currency:)
          lines = {}
          skipped = []
          Array(order.dig('lineItems', 'nodes')).each do |line|
            quantity = line['currentQuantity'].to_i
            next unless quantity.positive?

            variant = line['variant']
            unless orderable?(variant)
              skipped << { title: line['name'], quantity: quantity }
              next
            end
            same = lines[variant['id']] ||= { product: ProductSearch.present_product(variant['product'], currency: currency),
                                             variant: ProductSearch.present_variant(variant, currency: currency), quantity: 0 }
            same[:quantity] += quantity
          end
          { order_number: order['name'], lines: lines.values, skipped: skipped }
        end

        def self.orderable?(variant)
          product = variant && variant['product']
          product.present? && product['status'] == 'ACTIVE' && product['isGiftCard'] != true && variant['availableForSale'] == true
        end
        private_class_method :orderable?

        def self.money(set)
          shop = set && set['shopMoney']
          shop && { amount: shop['amount'], currency: shop['currencyCode'] }
        end

        # The parameters as recorded: each in its own shape and of a bounded
        # size, whatever was sent. A part of another shape is kept as INVALID;
        # one line more than allowed is kept, enough to refuse too many.
        def self.recordable(params)
          recorded = {
            'lines' => recordable_lines(params['lines']), 'discount' => recordable_discount(params['discount']),
            'shipping' => scalar(params['shipping']), 'delivery' => scalar(params['delivery'])
          }
          recorded.slice(*(RECORDED & params.keys))
        end

        def self.recordable_lines(lines)
          return lines if lines.nil?
          return INVALID unless lines.is_a?(Array)

          lines.first(MAX_LINES + 1).map do |line|
            next INVALID unless line.is_a?(Hash)

            line = line.to_h.stringify_keys
            { 'variant_id' => scalar(line['variant_id']), 'quantity' => scalar(line['quantity']) }
          end
        end

        def self.recordable_discount(discount)
          return discount if discount.blank?
          return INVALID unless discount.is_a?(Hash)

          discount.to_h.stringify_keys.slice('type', 'value').transform_values { |value| scalar(value) }
        end

        def self.scalar(value)
          case value
          when nil, Integer then value
          when String then value.first(TEXT_LENGTH)
          when Numeric, true, false then value.to_s
          else INVALID
          end
        end
        private_class_method :recordable_lines, :recordable_discount, :scalar

        # Why this order cannot be made, decided before the store is asked; nil
        # when it can. A preview does not need to know how the link is delivered.
        def refusal(preview: false)
          return 'no_customer' unless @customer

          sent = params['lines']
          return 'invalid_item' unless sent.nil? || sent.is_a?(Array)
          return 'no_items' if sent.blank?
          return 'too_many_items' if sent.size > MAX_LINES
          return 'invalid_item' unless sent.all? { |line| line.is_a?(Hash) && line['variant_id'].to_s.match?(VARIANT_ID) }
          return 'invalid_quantity' unless lines.all? { |line| line['quantity']&.between?(1, MAX_QUANTITY) }
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

        # Only the request that starts the action (given the customer) creates
        # a draft. A repeated request settles the earlier attempt: it looks
        # for its draft and sends the invoice only when the store did not send
        # it. A read that fails leaves the attempt unknown, never refused.
        def call
          if draft_id.nil? && @customer
            create_draft
          elsif draft_id.nil?
            state = look_for_lost_draft
            return state unless state == :found
          end
          deliver
        end

        # Settles an attempt whose answer was lost by reading the store only
        # (a panel read): its draft is looked for by the marker, and whether
        # the store emailed the invoice. Nothing is created or sent, so the
        # payment link may have reached no one; the note then says so.
        def resolve
          if draft_id.nil?
            state = look_for_lost_draft
            return unless state == :found
          end
          return if delivery == 'email' && invoice_sent?.nil?

          remember!(found_by_reading: true)
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

        # The lines as recorded: one per variant, quantities of repeated
        # variants added up. A quantity that is not a whole number of at least
        # one makes its line's quantity nil.
        def lines
          @lines ||= params['lines'].group_by { |line| line['variant_id'].to_s }.map do |variant, same|
            quantities = same.map { |line| Integer(line['quantity'].to_s, 10, exception: false) }
            { 'variant_id' => variant, 'quantity' => (quantities.sum if quantities.all? { |quantity| quantity&.positive? }) }
          end
        end

        # One discount for the whole order, a percentage or an amount; nil for none.
        def discount_input
          discount = params['discount']
          return if discount.blank?
          return :invalid unless discount.is_a?(Hash)

          type = DISCOUNT_TYPES[discount['type'].to_s]
          value = discount['value'].to_s
          return :invalid unless type && value.match?(AMOUNT) && value.to_d.positive?
          return :invalid if type == 'PERCENTAGE' && value.to_d > 100

          applied = { valueType: type, value: value.to_f, title: 'Discount' }
          applied[:amountWithCurrency] = { amount: value, currencyCode: currency } if type == 'FIXED_AMOUNT'
          applied
        end

        # No charge means a free custom rate. Omitting shippingLine lets
        # checkout select a store rate and add it to the total the agent saw.
        def shipping_input
          amount = params['shipping'].presence.to_s
          amount = '0' if amount.blank?
          return :invalid unless amount.match?(AMOUNT)

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

        # The draft an earlier attempt made, looked for by its marker once the
        # store's search can show it: :found; :unknown while it may not show
        # yet, or when the store could not be read; Refused when none was made.
        def look_for_lost_draft
          # `attempted` is written before the store is asked: without it, it never was.
          raise Refused, 'not_created' unless @record.progress['attempted']
          return :unknown if @record.created_at > LOOK_AFTER.ago

          case find_lost_draft
          when true then :found
          when false then raise Refused, 'not_created'
          else :unknown
          end
        rescue Error
          :unknown
        end

        # The draft with this action's marker among the customer's drafts made
        # from the helpdesk around the attempt, page by page, whatever their
        # status: true when found, false when none has it, nil when there are
        # more than can be looked through (then the attempt stays unknown).
        def find_lost_draft
          query = "#{self.class.drafts_query(customer_id, open: false)} #{created_around(@record.created_at)}"
          after = nil
          LOOK_PAGES.times do
            drafts = @store.query(:new_order_find_draft, { query: query, first: LOOK_PAGE, after: after })['draftOrders']
            found = Array(drafts['nodes']).find { |node| node.dig('marker', 'value') == @record.action_id }
            return remember_draft!(found) if found
            return false unless drafts.dig('pageInfo', 'hasNextPage')

            after = drafts.dig('pageInfo', 'endCursor')
          end
          nil
        end

        # The draft is made after its record is written, by a request that
        # ends within the runner's lease.
        def created_around(time)
          from = (time - CLOCK_SKEW).utc.iso8601
          to = (time + OrderActionRunner::LEASE + CLOCK_SKEW).utc.iso8601
          "created_at:>='#{from}' created_at:<='#{to}'"
        end

        # The store emails its invoice when the agent chose that; otherwise the
        # dialog puts the link into the reply. :unknown when the store could
        # not tell whether an earlier attempt sent it.
        def deliver
          return :accepted unless delivery == 'email'

          sent = invoice_sent?
          return :unknown if sent.nil?

          send_invoice unless sent
          :accepted
        end

        # Whether the invoice went out; nil when the store could not be read.
        # Only an attempt that asked for it (`invoice_asked`) can have sent it.
        def invoice_sent?
          return true if @record.progress['invoice_sent']
          return false unless @record.progress['invoice_asked']

          draft = @store.query(:new_order_draft, { id: draft_id })['draftOrder']
          sent = draft.present? && draft['invoiceSentAt'].present?
          remember!(invoice_sent: true) if sent
          sent
        rescue Error
          nil
        end

        # Written as asked before the store is asked, so that a later request
        # reads whether it went out instead of sending it again. When the
        # store surely did not send it, the draft goes and the action is
        # refused; when it may have, the attempt is unknown and the draft stays.
        def send_invoice
          remember!(invoice_asked: true)
          removing_draft_on_failure(draft_id, @record.progress['draft_name'], @store.record.shop_domain) do
            answer = @store.query(:new_order_invoice_send, { id: draft_id })['draftOrderInvoiceSend']
            user_errors!(answer['userErrors'])
          end
          remember!(invoice_sent: true)
        end
      end
    end
  end
end
