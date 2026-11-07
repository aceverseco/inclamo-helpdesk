# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

# The answers are recorded from a development store (order #1421: one shipped
# line, one unshipped catalogue line, two units of a tracked product).
RSpec.describe Inclamo::Shopify::OrderActionRunner, 'editing items' do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:order) { shopify_fixture('order_details_partly_shipped')['order'] }
  let(:lines) { order.dig('lineItems', 'nodes') }
  let(:shipped_line) { lines.find { |line| line['unfulfilledQuantity'].zero? } }
  let(:mug_line) { lines.find { |line| line['title'].start_with?('E2E Tracked Mug') } }
  let(:runner) { described_class.new(account: account, account_user: AccountUser.find_by(account: account, user: admin), conversation: conversation) }

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify(:order_details, data: { order: order })
    stub_shopify_fixture(:order_edit_begin, 'order_edit_begin_partly_shipped')
    stub_shopify_fixture(:order_edit_set_quantity, 'order_edit_set_quantity_reduced')
  end

  def mutation_requests(name)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^mutation #{name}\b/) && (!block_given? || yield(body['variables']))
    end
  end

  def preview(params)
    runner.edit_items_preview(order_id: order['id'], params: params)
  end

  def reduce_mug
    { 'lines' => [{ 'line_item_id' => mug_line['id'], 'quantity' => 1 }] }
  end

  describe 'summary' do
    it 'shows what the store calculates and changes nothing in the order' do
      summary = preview(reduce_mug)

      expect(summary).to include(difference: 'due_back', amount: '80.0', currency: 'UAH', customer_email: true)
      expect(summary[:total_before]).to eq(amount: '1745.9', currency: 'UAH')
      expect(summary[:total_after]).to eq(amount: '1665.9', currency: 'UAH')
      mug = summary[:lines].find { |line| line[:id] == mug_line['id'] }
      expect(mug).to include(quantity: 1, quantity_before: 2, editable: 2, restocking: true)
      expect(mutation_requests(:order_edit_set_quantity) { |variables| variables['quantity'] == 1 && variables['restock'] == true }).to have_been_made.once
      expect(mutation_requests(:order_edit_commit)).not_to have_been_made
      expect(Inclamo::OrderAction.count).to eq(0)
    end

    it 'puts every unit taken off back to stock, without asking' do
      preview({ 'lines' => [{ 'line_item_id' => mug_line['id'], 'quantity' => 0, 'restock' => false }] })

      expect(mutation_requests(:order_edit_set_quantity) { |variables| variables['quantity'].zero? && variables['restock'] == true }).to have_been_made.once
    end

    it 'adds a product the order does not hold as a new line' do
      stub_shopify_fixture(:order_edit_begin, 'order_edit_begin_with_variants')
      stub_shopify_fixture(:order_edit_add_variant, 'order_edit_add_variant')
      variant = 'gid://shopify/ProductVariant/67919901229214' # a snowboard the order does not hold

      summary = preview({ 'additions' => [{ 'variant_id' => variant, 'quantity' => 1 }] })

      expect(summary).to include(difference: 'owed', amount: '699.95')
      expect(summary[:added]).to contain_exactly(include(quantity: 1))
      expect(mutation_requests(:order_edit_begin) { |variables| variables['withVariants'] == true }).to have_been_made.once
      expect(mutation_requests(:order_edit_add_variant) { |variables| variables['variantId'] == variant && variables['quantity'] == 1 }).to have_been_made.once
    end

    it 'raises a product the order holds with units left to ship on its own line' do
      stub_shopify_fixture(:order_edit_begin, 'order_edit_begin_with_variants')
      mug_variant = 'gid://shopify/ProductVariant/67944221442206'

      preview({ 'additions' => [{ 'variant_id' => mug_variant, 'quantity' => 1 }] })

      calculated = mug_line['id'].sub('LineItem', 'CalculatedLineItem')
      expect(mutation_requests(:order_edit_set_quantity) { |variables| variables['lineItemId'] == calculated && variables['quantity'] == 3 }).to have_been_made.once
      expect(mutation_requests(:order_edit_add_variant)).not_to have_been_made
    end

    it 'refuses to change a shipped line, before the store is asked to' do
      expect { preview({ 'lines' => [{ 'line_item_id' => shipped_line['id'], 'quantity' => 0 }] }) }
        .to raise_error(Inclamo::Shopify::Actions::Refused) { |error| expect(error.code).to eq('item_shipped') }
      expect(mutation_requests(:order_edit_set_quantity)).not_to have_been_made
    end

    it 'refuses an unknown line, a negative quantity and an empty edit' do
      [[{ 'lines' => [{ 'line_item_id' => 'gid://shopify/LineItem/1', 'quantity' => 1 }] }, 'unknown_item'],
       [{ 'lines' => [{ 'line_item_id' => mug_line['id'], 'quantity' => -1 }] }, 'invalid_quantity'],
       [{ 'lines' => [{ 'line_item_id' => mug_line['id'], 'quantity' => 2 }] }, 'no_changes'],
       [{}, 'no_changes']].each do |params, code|
        expect { preview(params) }.to raise_error(Inclamo::Shopify::Actions::Refused) { |error| expect(error.code).to eq(code) }
      end
      expect(mutation_requests(:order_edit_set_quantity)).not_to have_been_made
    end

    it 'shows the store refusing the edit in its own words' do
      stub_shopify(:order_edit_begin, data: { orderEditBegin: { calculatedOrder: nil, userErrors: [{ field: nil, message: 'The order cannot be edited.' }] } })

      expect { preview(reduce_mug) }.to raise_error(Inclamo::Shopify::Actions::Refused) do |error|
        expect([error.code, error.message]).to eq(['store_refused', 'The order cannot be edited.'])
      end
    end

    it 'is not offered for a fully shipped or a cancelled order' do
      shipped = order.deep_dup.tap { |node| node['lineItems']['nodes'].each { |line| line['unfulfilledQuantity'] = 0 } }
      cancelled = order.deep_dup.merge('cancelledAt' => '2026-11-06T12:00:00Z')

      expect(Inclamo::Shopify::OrderPresenter.new(shipped, shop_domain: record.shop_domain).as_json[:actions]['edit_items'])
        .to eq(allowed: false, reason: 'already_shipped')
      expect(Inclamo::Shopify::OrderPresenter.new(cancelled, shop_domain: record.shop_domain).as_json[:actions]['edit_items'])
        .to eq(allowed: false, reason: 'already_cancelled')
      expect(Inclamo::Shopify::OrderPresenter.new(order, shop_domain: record.shop_domain).as_json[:actions]['edit_items'])
        .to eq(allowed: true, reason: nil)
    end

    it 'is refused to an agent without the role and without the scope, before the store is asked' do
      agent = create(:user, account: account, role: :agent)
      as_agent = described_class.new(account: account, account_user: AccountUser.find_by(account: account, user: agent), conversation: conversation)
      expect { as_agent.edit_items_preview(order_id: order['id'], params: reduce_mug) }
        .to raise_error(Inclamo::Shopify::Actions::Refused) { |error| expect(error.code).to eq('not_allowed') }

      record.update!(scopes: record.scopes - %w[write_order_edits read_order_edits])
      expect { preview(reduce_mug) }.to raise_error(Inclamo::Shopify::Actions::Refused) { |error| expect(error.code).to eq('missing_scope') }
      expect(record.reload.actions_report.find { |action| action[:name] == 'edit_items' }).to include(available: false, missing_scopes: %w[write_order_edits])
      expect(mutation_requests(:order_edit_begin)).not_to have_been_made
    end
  end

  describe 'saving' do
    let(:commit_answer) { shopify_fixture('order_edit_commit_reduced') }

    def save(params, id: 'action-edit-items-0001', as: runner)
      as.perform(action: 'edit_items', action_id: id, order_id: order['id'], params: params)
    end

    # The parameters with the summary the agent saw: the store's totals in a recorded answer.
    def agreed(params, fixture: 'order_edit_set_quantity_reduced', field: 'orderEditSetQuantity')
      calculated = shopify_fixture(fixture).dig(field, 'calculatedOrder')
      params.merge('expected' => { 'total_after' => calculated.dig('totalPriceSet', 'shopMoney', 'amount'),
                                   'balance' => calculated.dig('totalOutstandingSet', 'shopMoney', 'amount') })
    end

    def private_notes
      conversation.messages.where(private: true)
    end

    def commit_requests(&block)
      mutation_requests(:order_edit_commit, &block)
    end

    before { stub_shopify(:order_edit_commit, data: commit_answer) }

    it 'reduces a quantity, records the money due back and leaves a note by the agent' do
      result = save(agreed(reduce_mug))

      expect(result).to have_attributes(outcome: 'accepted', action: 'edit_items', order_number: '#1421')
      expect(commit_requests { |variables| variables['notify'] == false && variables['staffNote'] == 'Edited from the helpdesk' }).to have_been_made.once
      expect(result.progress).to include('committed' => true, 'difference' => 'due_back', 'amount' => '80.0', 'balance' => '-80.0')
      note = private_notes.sole
      expect(note.content).to eq("Edited the items of order #1421: #{mug_line['title']} from 2 to 1. 80.0 UAH is due back to the customer.")
      expect(note.sender).to eq(admin)
      expect(result.params).to eq(agreed(reduce_mug))
      expect(result.as_json[:result]).to eq('difference' => 'due_back', 'amount' => '80.0', 'currency' => 'UAH')
    end

    it 'removes a line, back to stock' do
      # The recorded reduction, with the line taken off instead (the totals are not looked at here).
      removed = shopify_fixture('order_edit_set_quantity_reduced').deep_dup
      mug = removed.dig('orderEditSetQuantity', 'calculatedOrder', 'lineItems', 'nodes').find { |line| line['title'] == mug_line['title'] }
      mug.merge!('quantity' => 0, 'editableQuantity' => 0)
      stub_shopify(:order_edit_set_quantity, data: removed)

      result = save(agreed({ 'lines' => [{ 'line_item_id' => mug_line['id'], 'quantity' => 0 }] }))

      expect(result.outcome).to eq('accepted')
      expect(mutation_requests(:order_edit_set_quantity) { |variables| variables['quantity'].zero? && variables['restock'] == true }).to have_been_made.once
      expect(private_notes.sole.content).to start_with("Edited the items of order #1421: #{mug_line['title']} removed (2).")
    end

    it 'adds a product and has the store notify the customer' do
      stub_shopify_fixture(:order_edit_begin, 'order_edit_begin_with_variants')
      stub_shopify_fixture(:order_edit_add_variant, 'order_edit_add_variant')
      owed = commit_answer.deep_dup.tap do |answer|
        answer['orderEditCommit']['order']['totalOutstandingSet']['shopMoney']['amount'] = '699.95'
        answer['orderEditCommit']['successMessages'] = ['Order updated', 'Invoice sent']
      end
      stub_shopify(:order_edit_commit, data: owed)

      result = save(agreed({ 'additions' => [{ 'variant_id' => 'gid://shopify/ProductVariant/67919901229214', 'quantity' => 1 }], 'notify' => true },
                           fixture: 'order_edit_add_variant', field: 'orderEditAddVariant'))

      expect(result.outcome).to eq('accepted')
      expect(commit_requests { |variables| variables['notify'] == true }).to have_been_made.once
      expect(result.progress).to include('difference' => 'owed', 'amount' => '699.95', 'store_said' => ['Order updated', 'Invoice sent'])
      expect(private_notes.sole.content).to match(/: .+ added \(1\)\. The customer owes 699\.95 UAH\. Customer notified\.\z/)
    end

    it 'commits once for one action id' do
      2.times { save(agreed(reduce_mug)) }

      expect(commit_requests).to have_been_made.once
      expect(private_notes.count).to eq(1)
    end

    it 'is refused to an agent without the role and without the scope, and the store is not asked' do
      agent = create(:user, account: account, role: :agent)
      as_agent = described_class.new(account: account, account_user: AccountUser.find_by(account: account, user: agent), conversation: conversation)
      expect(save(agreed(reduce_mug), as: as_agent).refusal).to eq('not_allowed')

      record.update!(scopes: record.scopes - %w[write_order_edits read_order_edits])
      expect(save(agreed(reduce_mug), id: 'action-edit-items-0002').refusal).to eq('missing_scope')
      expect(mutation_requests(:order_edit_begin)).not_to have_been_made
      expect(private_notes).to be_empty
    end

    it 'shows the store refusing the save and changes nothing' do
      stub_shopify(:order_edit_commit, data: { orderEditCommit: { order: nil, successMessages: nil, userErrors: [{ field: nil, message: 'The order cannot be edited.' }] } })

      result = save(agreed(reduce_mug))

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'The order cannot be edited.')
      expect(private_notes).to be_empty
    end

    it 'commits nothing when the store calculates differently from the summary the agent saw, and shows the new one' do
      seen = agreed(reduce_mug).deep_merge('expected' => { 'total_after' => '1700.0', 'balance' => '-45.9' })

      result = save(seen)

      expect(result).to have_attributes(outcome: 'refused', refusal: 'summary_changed')
      expect(result.as_json[:result]['summary']).to include('difference' => 'due_back', 'amount' => '80.0', 'total_after' => { 'amount' => '1665.9', 'currency' => 'UAH' })
      expect(commit_requests).not_to have_been_made
      expect(private_notes).to be_empty
    end

    it 'commits nothing without the summary the agent saw' do
      expect(save(reduce_mug).refusal).to eq('no_summary')
      expect(commit_requests).not_to have_been_made
    end

    describe 'the invoice for what the customer owes' do
      let(:board) { { 'additions' => [{ 'variant_id' => 'gid://shopify/ProductVariant/67919901229214', 'quantity' => 1 }] } }
      let(:owed) { commit_answer.deep_dup.tap { |answer| answer['orderEditCommit']['order']['totalOutstandingSet']['shopMoney']['amount'] = '699.95' } }

      def add_board(options, id = 'action-edit-items-0001')
        save(agreed(board.merge(options), fixture: 'order_edit_add_variant', field: 'orderEditAddVariant'), id: id)
      end

      def invoice_requests
        mutation_requests(:order_invoice_send) { |variables| variables['id'] == order['id'] }
      end

      before do
        stub_shopify_fixture(:order_edit_begin, 'order_edit_begin_with_variants')
        stub_shopify_fixture(:order_edit_add_variant, 'order_edit_add_variant')
        stub_shopify(:order_edit_commit, data: owed)
        stub_shopify_fixture(:order_invoice_send, 'order_invoice_send_sent')
      end

      it 'is emailed by the store after the save when chosen, once for one action id' do
        2.times { add_board('invoice' => true) }

        result = Inclamo::OrderAction.sole
        expect(result.outcome).to eq('accepted')
        expect(commit_requests).to have_been_made.once
        expect(invoice_requests).to have_been_made.once
        expect(result.as_json[:result]).to include('difference' => 'owed', 'amount' => '699.95', 'invoice' => 'sent')
        expect(private_notes.sole.content).to end_with('The customer owes 699.95 UAH. The store emailed its invoice to the customer.')
      end

      it 'is not sent a second time when the store notifies the customer: its email carries the invoice' do
        result = add_board('invoice' => true, 'notify' => true)

        expect(result.outcome).to eq('accepted')
        expect(commit_requests { |variables| variables['notify'] == true }).to have_been_made.once
        expect(mutation_requests(:order_invoice_send)).not_to have_been_made
        expect(result.progress).not_to have_key('invoice')
      end

      it 'is not sent when the customer owes nothing, or when not chosen' do
        save(agreed(reduce_mug.merge('invoice' => true)))
        add_board({}, 'action-edit-items-0002')

        expect(mutation_requests(:order_invoice_send)).not_to have_been_made
      end

      it 'needs an email on the order: the summary says whether there is one, and nothing is saved without it' do
        no_email = shopify_fixture('order_edit_add_variant').deep_dup
        no_email.dig('orderEditAddVariant', 'calculatedOrder', 'originalOrder')['email'] = nil
        stub_shopify(:order_edit_add_variant, data: no_email)

        expect(preview(board)).to include(difference: 'owed', customer_email: false)
        expect(add_board('invoice' => true)).to have_attributes(outcome: 'refused', refusal: 'no_email')
        expect(commit_requests).not_to have_been_made
      end

      it 'keeps the edit when the store refuses the invoice, and says so' do
        stub_shopify_fixture(:order_invoice_send, 'order_invoice_send_nothing_owed')

        result = add_board('invoice' => true)

        expect(result.outcome).to eq('accepted')
        expect(result.progress).to include('committed' => true, 'invoice' => 'refused', 'invoice_message' => 'No outstanding balance exist')
        expect(private_notes.sole.content).to end_with('The store did not send the invoice.')
      end

      it 'is never sent again when its answer was lost' do
        stub_request(:post, shopify_graphql_url).with { |request| JSON.parse(request.body)['query'].match?(/^mutation order_invoice_send\b/) }.to_timeout

        result = add_board('invoice' => true)

        expect(result.outcome).to eq('accepted')
        expect(result.progress).to include('invoice' => 'unknown')
        expect(private_notes.sole.content).to end_with('It is not known whether the invoice was sent.')
        expect(invoice_requests).to have_been_made.once
      end

      it 'is never sent again after an attempt that stopped while sending it' do
        add_board('invoice' => true)
        record = Inclamo::OrderAction.sole
        record.update!(outcome: 'unknown', completed_at: nil, progress: record.progress.merge('invoice' => 'sending'))

        runner.settle_open!

        expect(record.reload).to have_attributes(outcome: 'accepted')
        expect(record.progress).to include('invoice' => 'unknown')
        expect(invoice_requests).to have_been_made.once
      end
    end

    describe 'when the answer to the save was lost' do
      before { stub_request(:post, shopify_graphql_url).with { |request| JSON.parse(request.body)['query'].match?(/^mutation order_edit_commit\b/) }.to_timeout }

      def store_now(total:, mug_quantity:)
        calculated = shopify_fixture('order_edit_begin_partly_shipped').dig('orderEditBegin', 'calculatedOrder').deep_dup
        calculated['originalOrder']['currentTotalPriceSet']['shopMoney']['amount'] = total
        calculated['lineItems']['nodes'].find { |line| line['id'] == mug_line['id'].sub('LineItem', 'CalculatedLineItem') }['quantity'] = mug_quantity
        stub_shopify(:order_edit_begin, data: { orderEditBegin: { calculatedOrder: calculated, userErrors: [] } })
      end

      it 'is unknown, then accepted without a second save when the store holds the edit' do
        expect(save(agreed(reduce_mug)).outcome).to eq('unknown')
        expect(private_notes).to be_empty

        store_now(total: '1665.9', mug_quantity: 1)
        runner.settle_open!

        expect(Inclamo::OrderAction.sole.outcome).to eq('accepted')
        expect(commit_requests).to have_been_made.once
        expect(private_notes.count).to eq(1)
      end

      it 'saves again when the order is as it was before' do
        expect(save(agreed(reduce_mug)).outcome).to eq('unknown')

        stub_shopify(:order_edit_commit, data: commit_answer)
        runner.settle_open!

        expect(Inclamo::OrderAction.sole.outcome).to eq('accepted')
        expect(commit_requests).to have_been_made.twice
      end

      it 'stays unknown when the order changed some other way' do
        expect(save(agreed(reduce_mug)).outcome).to eq('unknown')

        store_now(total: '1500.0', mug_quantity: 2)
        runner.settle_open!

        expect(Inclamo::OrderAction.sole.outcome).to eq('unknown')
        expect(commit_requests).to have_been_made.once
      end
    end
  end
end
