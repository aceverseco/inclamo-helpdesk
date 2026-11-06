# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderActionRunner, 'refund and replacement' do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:order) { shopify_fixture('order_details_open')['order'] }
  let(:currency) { order['currencyCode'] }
  let(:total) { order.dig('totalPriceSet', 'shopMoney', 'amount') }
  let(:lines) { order.dig('lineItems', 'nodes') }
  let(:runner) { described_class.new(account: account, account_user: AccountUser.find_by(account: account, user: admin), conversation: conversation) }

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify(:order_details, data: { order: order })
  end

  # Requests of one mutation; with a block, only those whose variables it accepts.
  def mutation_requests(name)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^mutation #{name}\b/) && (!block_given? || yield(body['variables']))
    end
  end

  def notes
    conversation.messages.where(private: true).pluck(:content)
  end

  describe 'refund' do
    def stub_suggestion(amount: total)
      stub_shopify(:refund_suggestion, data: { order: { id: order['id'], name: order['name'], currencyCode: currency, suggestedRefund: {
                     amountSet: { shopMoney: { amount: amount, currencyCode: currency } },
                     maximumRefundableSet: { shopMoney: { amount: total, currencyCode: currency } },
                     shipping: { amountSet: { shopMoney: { amount: '0.0', currencyCode: currency } }, maximumRefundableSet: { shopMoney: { amount: '0.0', currencyCode: currency } } },
                     refundLineItems: lines.map { |line| { lineItem: { id: line['id'] }, quantity: line['quantity'], restockType: 'NO_RESTOCK' } },
                     suggestedTransactions: [{ gateway: 'manual', formattedGateway: 'Manual', kind: 'SUGGESTED_REFUND',
                                               amountSet: { shopMoney: { amount: amount, currencyCode: currency } },
                                               maximumRefundableSet: { shopMoney: { amount: total, currencyCode: currency } },
                                               parentTransaction: { id: 'gid://shopify/OrderTransaction/1' } }]
                   } } })
    end

    def stub_refund(amount)
      stub_shopify(:refund_create, data: { refundCreate: { refund: { id: 'gid://shopify/Refund/1', totalRefundedSet: { shopMoney: { amount: amount, currencyCode: currency } } }, userErrors: [] } })
    end

    def refund(params, id: 'action-refund-0001')
      runner.perform(action: 'refund', action_id: id, order_id: order['id'], params: params)
    end

    it 'refunds part of an order by amount, once, through the payment the store proposes' do
      stub_suggestion
      stub_refund('20.0')

      result = refund({ 'mode' => 'amount', 'amount' => '20.00' })

      expect(result).to have_attributes(outcome: 'accepted', params: { 'mode' => 'amount', 'amount' => '20.00' })
      expect(result.progress['refunded']).to eq("20.0 #{currency}")
      expect(mutation_requests('refund_create') do |variables|
        variables['key'] == 'action-refund-0001' &&
          variables.dig('input', 'transactions') == [{ 'parentId' => 'gid://shopify/OrderTransaction/1', 'gateway' => 'manual', 'amount' => '20.0', 'orderId' => order['id'], 'kind' => 'REFUND' }] &&
          !variables['input'].key?('refundLineItems')
      end).to have_been_made.once
      expect(notes).to eq(["Refunded 20.0 #{currency} on order #1001."])
    end

    it 'refuses an amount above what remains refundable, before asking the store for a refund' do
      result = refund({ 'mode' => 'amount', 'amount' => (total.to_d + 1).to_s('F') })

      expect(result).to have_attributes(outcome: 'refused', refusal: 'above_refundable')
      expect(mutation_requests('refund_create')).not_to have_been_made
      expect(notes).to be_empty
    end

    it 'refuses an amount that is not a positive number' do
      expect(refund({ 'mode' => 'amount', 'amount' => '-5' }, id: 'action-refund-0002').refusal).to eq('invalid_amount')
      expect(refund({ 'mode' => 'amount', 'amount' => 'ten' }, id: 'action-refund-0003').refusal).to eq('invalid_amount')
    end

    context 'when items are put back in stock' do
      let(:here) { { 'id' => 'gid://shopify/Location/1', 'name' => 'Shop location' } }
      let(:there) { { 'id' => 'gid://shopify/Location/2', 'name' => 'Warehouse' } }
      let(:with_locations) { record.update!(scopes: record.scopes + %w[read_locations]) }

      def stub_locations(*found)
        stub_shopify(:locations, data: { locations: { nodes: found } })
      end

      def locations_requests
        a_request(:post, shopify_graphql_url).with { |request| JSON.parse(request.body)['query'].match?(/^query locations\b/) }
      end

      # A refund whose lines are exactly these [kind, quantity] pairs, each at the location.
      def restocked(location, *entries)
        mutation_requests('refund_create') do |variables|
          items = variables.dig('input', 'refundLineItems')
          items.map { |item| [item['restockType'], item['quantity']] } == entries && items.all? { |item| item['locationId'] == location['id'] }
        end
      end

      before do
        stub_suggestion
        stub_refund(total)
      end

      it 'sends items that have not shipped back as cancellations at the only location of the store' do
        with_locations
        stub_locations(here)

        refund({ 'mode' => 'full', 'restock' => true, 'notify' => true })

        expect(restocked(here, *lines.map { ['CANCEL', 1] })).to have_been_made.once
        expect(mutation_requests('refund_create') { |variables| variables.dig('input', 'notify') == true && variables.dig('input', 'transactions').first['amount'] == total })
          .to have_been_made.once
      end

      context 'when they have shipped' do
        let(:order) { shopify_fixture('order_details_shipped')['order'] }

        it 'sends them back as returns, and names the location in the confirmation' do
          with_locations
          stub_locations(here)

          preview = runner.refund_preview(order_id: order['id'], params: { 'mode' => 'full', 'restock' => true })
          expect(preview).to include(restocked_items: lines.size, locations: [here], location_id: here['id'], left_out_items: 0, missing_scope: nil)

          expect(refund({ 'mode' => 'full', 'restock' => true }).outcome).to eq('accepted')
          expect(restocked(here, *lines.map { ['RETURN', 1] })).to have_been_made.once
        end

        it 'asks which location when the store has several, and refunds nothing until one is chosen' do
          with_locations
          stub_locations(here, there)

          preview = runner.refund_preview(order_id: order['id'], params: { 'mode' => 'full', 'restock' => true })
          expect(preview).to include(restocked_items: lines.size, locations: [here, there], location_id: nil)

          expect(refund({ 'mode' => 'full', 'restock' => true })).to have_attributes(outcome: 'refused', refusal: 'location_needed')
          expect(mutation_requests('refund_create')).not_to have_been_made

          chosen = refund({ 'mode' => 'full', 'restock' => true, 'location_id' => there['id'] }, id: 'action-refund-0006')
          expect(chosen).to have_attributes(outcome: 'accepted', params: include('location_id' => there['id']))
          expect(restocked(there, *lines.map { ['RETURN', 1] })).to have_been_made.once
        end

        it 'refuses a location the store does not have' do
          with_locations
          stub_locations(here, there)

          expect(refund({ 'mode' => 'full', 'restock' => true, 'location_id' => 'gid://shopify/Location/3' }).refusal).to eq('unknown_location')
          expect(mutation_requests('refund_create')).not_to have_been_made
        end

        it 'does not ask for locations when nothing is to be restocked' do
          with_locations

          expect(refund({ 'mode' => 'full' }).outcome).to eq('accepted')
          expect(locations_requests).not_to have_been_made
          expect(mutation_requests('refund_create') { |variables| variables.dig('input', 'refundLineItems').all? { |item| item['restockType'] == 'NO_RESTOCK' && !item.key?('locationId') } })
            .to have_been_made.once
        end
      end

      context 'when a line has shipped in part' do
        let(:order) do
          shopify_fixture('order_details_open')['order'].tap do |found|
            found['lineItems']['nodes'] = [found['lineItems']['nodes'].first.merge('quantity' => 3, 'refundableQuantity' => 3, 'unfulfilledQuantity' => 1)]
          end
        end

        it 'sends the unit that has not shipped as a cancellation and the others as a return' do
          with_locations
          stub_locations(here)

          refund({ 'mode' => 'items', 'restock' => true, 'items' => [{ 'line_item_id' => lines.first['id'], 'quantity' => 3 }] })

          expect(restocked(here, ['CANCEL', 1], ['RETURN', 2])).to have_been_made.once
        end

        it 'counts units that have not shipped first' do
          with_locations
          stub_locations(here)

          refund({ 'mode' => 'items', 'restock' => true, 'items' => [{ 'line_item_id' => lines.first['id'], 'quantity' => 1 }] })

          expect(restocked(here, ['CANCEL', 1])).to have_been_made.once
        end
      end

      it 'restocks nothing when the app cannot read locations, and says so in the confirmation' do
        preview = runner.refund_preview(order_id: order['id'], params: { 'mode' => 'full', 'restock' => true })
        expect(preview).to include(restocked_items: 0, locations: [], left_out_items: lines.size, missing_scope: 'read_locations')

        expect(refund({ 'mode' => 'full', 'restock' => true }).outcome).to eq('accepted')
        expect(locations_requests).not_to have_been_made
        expect(mutation_requests('refund_create') { |variables| variables.dig('input', 'refundLineItems').all? { |item| item['restockType'] == 'NO_RESTOCK' && !item.key?('locationId') } })
          .to have_been_made.once
      end
    end

    it 'refunds chosen items, within the quantity that can still be refunded' do
      stub_suggestion(amount: '100.0')
      stub_refund('100.0')
      first = lines.first

      expect(refund({ 'mode' => 'items', 'items' => [{ 'line_item_id' => first['id'], 'quantity' => 1 }] }).outcome).to eq('accepted')
      expect(refund({ 'mode' => 'items', 'items' => [{ 'line_item_id' => first['id'], 'quantity' => 99 }] }, id: 'action-refund-0004').refusal).to eq('invalid_quantity')
      expect(refund({ 'mode' => 'items', 'items' => [{ 'line_item_id' => 'gid://shopify/LineItem/0', 'quantity' => 1 }] }, id: 'action-refund-0005').refusal).to eq('unknown_item')
    end

    it 'makes one refund when the answer was lost and the same confirmation is sent again' do
      stub_suggestion
      lost = stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation refund_create') }.to_timeout

      first = refund({ 'mode' => 'amount', 'amount' => '20.00' })
      expect(first.outcome).to eq('unknown')
      expect(notes).to be_empty

      remove_request_stub(lost)
      stub_refund('20.0')
      second = refund({ 'mode' => 'amount', 'amount' => '20.00' })

      expect(second.id).to eq(first.id)
      expect(second.outcome).to eq('accepted')
      # Both requests carried the same idempotency key: the store makes one refund of them.
      expect(mutation_requests('refund_create') { |variables| variables['key'] == 'action-refund-0001' }).to have_been_made.twice
      expect(Inclamo::OrderAction.where(action: 'refund').count).to eq(1)
      expect(notes.size).to eq(1)
    end

    it 'shows the reason of the store when it refuses the refund' do
      stub_suggestion
      stub_shopify(:refund_create, data: { refundCreate: { refund: nil, userErrors: [{ field: ['transactions'], message: 'Refund amount exceeds the amount available' }] } })

      expect(refund({ 'mode' => 'amount', 'amount' => '20.00' })).to have_attributes(outcome: 'refused', store_message: 'Refund amount exceeds the amount available')
    end

    it 'shows in the confirmation the amount, its currency and where the money goes, without changing anything' do
      stub_suggestion

      preview = runner.refund_preview(order_id: order['id'], params: { 'mode' => 'amount', 'amount' => '20.00', 'notify' => true })

      expect(preview).to include(amount: '20.0', currency: currency, maximum: total.to_d.to_s('F'), notify: true, destinations: [{ gateway: 'Manual', amount: '20.0' }])
      expect(mutation_requests('refund_create')).not_to have_been_made
      expect(Inclamo::OrderAction.count).to eq(0)
    end
  end

  describe 'free replacement' do
    let(:draft_id) { 'gid://shopify/DraftOrder/77' }
    let(:kept) { [{ 'line_item_id' => lines.first['id'], 'quantity' => 1 }] }

    def stub_draft_create
      stub_shopify(:replacement_draft_create, data: { draftOrderCreateFromOrder: { draftOrder: { id: draft_id, name: '#D7', lineItems: {
                     nodes: lines.each_with_index.map { |line, index| { id: "gid://shopify/DraftOrderLineItem/#{index}", title: line['title'], quantity: line['quantity'], custom: false, variant: { id: "gid://shopify/ProductVariant/#{index + 1}" } } }
                   } }, userErrors: [] } })
    end

    def stub_draft_update(total: '0.0', errors: [])
      stub_shopify(:replacement_draft_update, data: { draftOrderUpdate: { draftOrder: errors.empty? ? { id: draft_id, totalPriceSet: { shopMoney: { amount: total, currencyCode: currency } } } : nil, userErrors: errors } })
    end

    def stub_draft_complete(errors: [])
      stub_shopify(:replacement_draft_complete, data: { draftOrderComplete: { draftOrder: errors.empty? ? { id: draft_id, order: { id: 'gid://shopify/Order/9', name: '#1050' } } : nil, userErrors: errors } })
    end

    def stub_draft_delete(errors: [])
      stub_shopify(:replacement_draft_delete, data: { draftOrderDelete: { deletedId: errors.empty? ? draft_id : nil, userErrors: errors } })
    end

    def replace(params = { 'items' => kept }, id: 'action-replacement-0001')
      runner.perform(action: 'replacement', action_id: id, order_id: order['id'], params: params)
    end

    it 'creates a new order with the kept items, fully discounted, shipping free, naming the original' do
      stub_draft_create
      stub_draft_update
      stub_draft_complete

      result = replace

      expect(result.outcome).to eq('accepted')
      expect(result.progress).to include('new_order_number' => '#1050')
      expect(mutation_requests('replacement_draft_update') do |variables|
        input = variables['input']
        input['lineItems'] == [{ 'variantId' => 'gid://shopify/ProductVariant/1', 'quantity' => 1 }] &&
          input['appliedDiscount'].slice('valueType', 'value') == { 'valueType' => 'PERCENTAGE', 'value' => 100 } &&
          input.dig('shippingLine', 'priceWithCurrency', 'amount') == '0' && input['tags'] == ['replacement'] && input['note'].include?('#1001')
      end).to have_been_made.once
      expect(notes).to eq(['Created replacement order #1050 for order #1001, free of charge.'])
    end

    it 'keeps every item when the agent removed none' do
      stub_draft_create
      stub_draft_update
      stub_draft_complete

      replace({})

      expect(mutation_requests('replacement_draft_update') { |variables| variables.dig('input', 'lineItems').size == lines.size }).to have_been_made.once
    end

    it 'does not let the agent add quantity or unknown items, and creates nothing then' do
      expect(replace({ 'items' => [{ 'line_item_id' => lines.first['id'], 'quantity' => lines.first['quantity'] + 1 }] }).refusal).to eq('invalid_quantity')
      expect(replace({ 'items' => [{ 'line_item_id' => 'gid://shopify/LineItem/0', 'quantity' => 1 }] }, id: 'action-replacement-0002').refusal).to eq('unknown_item')
      expect(mutation_requests('replacement_draft_create')).not_to have_been_made
    end

    it 'removes the draft when the store cannot supply an item, so nothing is left behind' do
      stub_draft_create
      stub_draft_update
      stub_draft_complete(errors: [{ field: ['id'], message: 'Item is no longer available' }])
      stub_draft_delete

      result = replace

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'Item is no longer available')
      expect(mutation_requests('replacement_draft_delete')).to have_been_made.once
      expect(notes).to be_empty
    end

    it 'names the draft with a link when it could not be removed' do
      stub_draft_create
      stub_draft_update(errors: [{ field: ['lineItems'], message: 'Variant is unavailable' }])
      stub_draft_delete(errors: [{ field: ['id'], message: 'Draft order is locked' }])

      result = replace

      expect(result.outcome).to eq('refused')
      expect(result.store_message).to include('Variant is unavailable', '#D7', 'https://admin.shopify.com/store/example-store/draft_orders/77')
    end

    it 'does not complete a replacement that would cost the customer anything' do
      stub_draft_create
      stub_draft_update(total: '12.5')
      stub_draft_delete

      result = replace

      expect(result.refusal).to eq('not_free')
      expect(mutation_requests('replacement_draft_complete')).not_to have_been_made
    end

    it 'makes one order when the answer to the completion was lost and the confirmation is sent again' do
      stub_draft_create
      stub_draft_update
      lost = stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation replacement_draft_complete') }.to_timeout

      first = replace
      expect(first.outcome).to eq('unknown')

      remove_request_stub(lost)
      stub_shopify(:replacement_draft, data: { draftOrder: { id: draft_id, name: '#D7', status: 'COMPLETED', order: { id: 'gid://shopify/Order/9', name: '#1050' } } })
      second = replace

      expect(second.id).to eq(first.id)
      expect(second.outcome).to eq('accepted')
      expect(second.progress['new_order_number']).to eq('#1050')
      expect(mutation_requests('replacement_draft_create')).to have_been_made.once
      expect(mutation_requests('replacement_draft_complete')).to have_been_made.once
      expect(notes.size).to eq(1)
    end

    it 'is unavailable without the draft orders scope or the products scope, naming the scope' do
      record.update!(scopes: %w[read_customers read_orders write_orders read_products])
      expect(replace.refusal).to eq('missing_scope')
      expect(record.missing_scopes_for('replacement')).to eq(%w[write_draft_orders])

      record.update!(scopes: %w[read_customers read_orders write_orders write_draft_orders])
      expect(record.missing_scopes_for('replacement')).to eq(%w[read_products])
      expect(record.unavailable_reason('refund')).to be_nil
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation') }
    end
  end
end
