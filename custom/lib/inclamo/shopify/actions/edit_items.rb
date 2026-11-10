# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Changes the items of an order that has not fully shipped: the quantity
      # of a line, a line taken off, a product added. The store edits an order
      # in a session that changes nothing until it is committed; each summary
      # and each save opens a fresh one and stages the agent's changes on it,
      # so an abandoned dialog leaves nothing behind (design D1).
      #
      # Parameters, as the dialog sends them:
      #   lines      [{ line_item_id, quantity }]  the new quantity of a line, 0 takes it off
      #   additions  [{ variant_id, quantity }]    products from the catalogue
      #   notify     the store emails the customer the change
      #   invoice    the store emails an invoice for what the customer owes
      #   expected   { total_after, balance } of the summary the agent saw
      # Units taken off an order go back to stock: they never left the shelf.
      # Money due back is not refunded here: the panel leads the agent into the
      # refund dialog with the amount (design D3).
      class EditItems < Base
        RECORDED = %w[lines additions notify invoice expected].freeze
        STAFF_NOTE = 'Edited from the helpdesk'

        # What the order becomes, as the store calculates it. Nothing is committed.
        def preview
          summary(staged_session)
        end

        def call
          if @record.progress['committed']
            invoice!
            return :accepted
          end
          return after_lost_answer if @record.progress['committing']

          commit!(staged_session)
        end

        # Reading a conversation may confirm a completed edit, but cannot
        # commit another edit or send an invoice. Retrying is an explicit POST.
        def resolve
          if @record.progress['committed']
            invoice_unconfirmed!
            return :accepted
          end
          after_lost_answer(read_only: true) if @record.progress['committing']
        end

        private

        def invoice_unconfirmed!
          return unless invoice_wanted?(@record.progress['difference'])

          remember!(invoice: 'unknown') if [nil, 'sending'].include?(@record.progress['invoice'])
        end

        def commit!(calculated)
          facts = summary(calculated)
          unchanged_since_summary!(facts)
          # The invoice goes to the order's email; without one nothing is saved (as for a new order).
          raise Refused, 'no_email' if invoice_wanted?(facts[:difference]) && !facts[:customer_email]

          remember!(committing: true, targets: @targets, total_before: facts.dig(:total_before, :amount), total_after: facts.dig(:total_after, :amount),
                    difference: facts[:difference], amount: facts[:amount], currency: facts[:currency], changes: changes_of(facts))
          answer = @store.query(:order_edit_commit, { id: calculated['id'], notify: params['notify'] == true, staffNote: STAFF_NOTE })['orderEditCommit']
          user_errors!(answer['userErrors'])
          balance = answer.dig('order', 'totalOutstandingSet', 'shopMoney', 'amount')
          remember!(committed: true, balance: balance, store_said: Array(answer['successMessages']))
          invoice!
          :accepted
        end

        # One email with the payment link (founder, 2026-11-06): when the store
        # notifies the customer of the change, its email already carries the
        # invoice for the balance, so no second one is sent.
        def invoice_wanted?(difference)
          params['invoice'] == true && params['notify'] != true && difference == 'owed'
        end

        # The store's invoice for what the customer owes, after the commit. The
        # edit is saved whatever happens here; the record says whether the
        # invoice went out. It is never sent twice: an attempt whose answer was
        # lost stays unknown.
        def invoice!
          return unless invoice_wanted?(@record.progress['difference'])

          case @record.progress['invoice']
          when nil then nil
          when 'sending' then return remember!(invoice: 'unknown')
          else return
          end

          remember!(invoice: 'sending')
          answer = @store.query(:order_invoice_send, { id: @record.order_id })['orderInvoiceSend']
          user_errors!(answer['userErrors'])
          remember!(invoice: 'sent')
        rescue Refused, Error::QueryError => e
          remember!(invoice: 'refused', invoice_message: e.message.first(500))
        rescue Error => e
          remember!(invoice: e.outcome_unknown? ? 'unknown' : 'refused', invoice_message: e.class.name.demodulize.underscore)
        end

        # The store's fresh calculation must be the one the agent agreed to;
        # otherwise nothing is committed and the agent is shown the new one.
        def unchanged_since_summary!(facts)
          expected = params['expected'].to_h.stringify_keys
          raise Refused, 'no_summary' if expected['total_after'].blank? || expected['balance'].blank?

          same = ->(value, known) { BigDecimal(value.to_s) == BigDecimal(known.to_s) }
          return if same.call(expected['total_after'], facts.dig(:total_after, :amount)) && same.call(expected['balance'], facts.dig(:balance, :amount))

          remember!(summary: facts)
          raise Refused, 'summary_changed'
        rescue ArgumentError, TypeError
          raise Refused, 'no_summary'
        end

        # The commit was sent and its answer lost. A fresh session, never
        # committed, shows the order as it is now: the edit is there, the order
        # is as it was before (then it is made again), or it cannot be told.
        def after_lost_answer(read_only: false)
          answer = @store.query(:order_edit_begin, { id: @record.order_id, withVariants: false })['orderEditBegin']
          user_errors!(answer['userErrors'])
          calculated = answer['calculatedOrder'] or raise Refused, 'store_refused'
          total = BigDecimal(calculated.dig('originalOrder', 'currentTotalPriceSet', 'shopMoney', 'amount') || '0')
          quantities = Array(calculated.dig('lineItems', 'nodes')).to_h { |line| [line['id'], line['quantity'].to_i] }
          targets = @record.progress['targets'] || {}
          if total == BigDecimal(@record.progress['total_after'].to_s) && targets.all? { |id, quantity| quantities[id] == quantity }
            remember!(committed: true)
            read_only ? invoice_unconfirmed! : invoice!
            :accepted
          elsif !read_only && total == BigDecimal(@record.progress['total_before'].to_s) && targets.none? { |id, quantity| quantities[id] == quantity }
            remember!(committing: false)
            commit!(staged_session)
          else
            :unknown
          end
        end

        # Each change as the private note names it.
        def changes_of(facts)
          name = ->(line) { [line[:title], line[:variant]].compact.reject { |part| part == 'Default Title' }.join(' — ') }
          changed = facts[:lines].reject { |line| line[:quantity] == line[:quantity_before] }.map do |line|
            if line[:quantity].zero?
              I18n.t('inclamo.order_actions.notes.edit.removed', title: name.call(line), from: line[:quantity_before])
            else
              I18n.t('inclamo.order_actions.notes.edit.quantity', title: name.call(line), from: line[:quantity_before], to: line[:quantity])
            end
          end
          changed + facts[:added].map { |line| I18n.t('inclamo.order_actions.notes.edit.added', title: name.call(line), quantity: line[:quantity]) }
        end

        def wanted_lines
          @wanted_lines ||= Array(params['lines']).map do |item|
            item = item.to_h.stringify_keys
            quantity = Integer(item['quantity'], exception: false)
            raise Refused, 'invalid_quantity' if quantity.nil? || quantity.negative?

            { id: item['line_item_id'].to_s, quantity: quantity }
          end
        end

        def wanted_additions
          @wanted_additions ||= Array(params['additions']).map do |item|
            item = item.to_h.stringify_keys
            quantity = Integer(item['quantity'], exception: false)
            raise Refused, 'invalid_quantity' unless quantity&.positive?
            raise Refused, 'unknown_variant' unless item['variant_id'].to_s.start_with?('gid://shopify/ProductVariant/')

            { variant_id: item['variant_id'].to_s, quantity: quantity }
          end
        end

        # Opens a session, stages every change and returns the calculated order.
        def staged_session
          raise Refused, 'no_changes' if wanted_lines.empty? && wanted_additions.empty?

          answer = @store.query(:order_edit_begin, { id: @record.order_id, withVariants: wanted_additions.any? })['orderEditBegin']
          user_errors!(answer['userErrors'])
          calculated = answer['calculatedOrder'] or raise Refused, 'store_refused'
          targets, added = plan(calculated)
          raise Refused, 'no_changes' if targets.empty? && added.empty?

          @targets = targets

          targets.each do |line_id, quantity|
            calculated = stage(:order_edit_set_quantity, 'orderEditSetQuantity',
                               { id: calculated['id'], lineItemId: line_id, quantity: quantity, restock: true })
          end
          added.each do |addition|
            calculated = stage(:order_edit_add_variant, 'orderEditAddVariant',
                               { id: calculated['id'], variantId: addition[:variant_id], quantity: addition[:quantity] })
          end
          calculated
        end

        # The quantity each changed line is set to, and the products that need a
        # line of their own. A product already on a line with units left to ship
        # is raised on that line: the store refuses the same variant twice.
        def plan(calculated)
          lines = Array(calculated.dig('lineItems', 'nodes')).index_by { |line| line['id'] }
          targets = {}
          wanted_lines.each do |wanted|
            line = lines[calculated_id(wanted[:id])] or raise Refused, 'unknown_item'
            editable = line['editableQuantity'].to_i
            raise Refused, 'item_shipped' unless editable.positive?
            # Shipped units of a partly shipped line stay on it.
            raise Refused, 'invalid_quantity' if wanted[:quantity] < line['quantity'].to_i - editable

            targets[line['id']] = wanted[:quantity] unless wanted[:quantity] == line['quantity'].to_i
          end
          added = []
          wanted_additions.each do |addition|
            line = lines.values.find { |candidate| candidate.dig('variant', 'id') == addition[:variant_id] && candidate['editableQuantity'].to_i.positive? }
            if line
              targets[line['id']] = (targets[line['id']] || line['quantity'].to_i) + addition[:quantity]
            else
              added << addition
            end
          end
          [targets, added]
        end

        # An order's line and the same line in an edit session share their number.
        def calculated_id(line_item_id)
          number = line_item_id.to_s.split('/').last
          "gid://shopify/CalculatedLineItem/#{number}"
        end

        def stage(document, field, variables)
          answer = @store.query(document, variables)[field]
          user_errors!(answer['userErrors'])
          answer['calculatedOrder'] or raise Refused, 'store_refused'
        end

        def money(bag)
          value = bag&.dig('shopMoney') || {}
          { amount: value['amount'], currency: value['currencyCode'] }
        end

        # What the dialog shows: the totals before and after, and what the
        # change means for the money: owed by the customer, due back, or none.
        def summary(calculated)
          balance = BigDecimal(calculated.dig('totalOutstandingSet', 'shopMoney', 'amount') || '0')
          {
            currency: calculated.dig('originalOrder', 'currencyCode'),
            total_before: money(calculated.dig('originalOrder', 'currentTotalPriceSet')),
            total_after: money(calculated['totalPriceSet']),
            balance: money(calculated['totalOutstandingSet']),
            difference: if balance.positive? then 'owed'
                        elsif balance.negative? then 'due_back'
                        else 'none'
                        end,
            amount: balance.abs.to_s('F'),
            # Whether an invoice can be emailed: the address itself is not passed on.
            customer_email: calculated.dig('originalOrder', 'email').present?,
            lines: Array(calculated.dig('lineItems', 'nodes')).map do |line|
              { id: line['id'].sub('CalculatedLineItem', 'LineItem'), title: line['title'], variant: line['variantTitle'], quantity: line['quantity'],
                quantity_before: line['quantity'].to_i - line['editableQuantity'].to_i + line['editableQuantityBeforeChanges'].to_i,
                editable: line['editableQuantityBeforeChanges'].to_i, restocking: line['restocking'], unit_price: money(line['discountedUnitPriceSet']) }
            end,
            added: Array(calculated.dig('addedLineItems', 'nodes')).map do |line|
              { title: line['title'], variant: line['variantTitle'], quantity: line['quantity'], unit_price: money(line['discountedUnitPriceSet']) }
            end
          }
        end
      end
    end
  end
end
