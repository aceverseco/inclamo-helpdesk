# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::MacroSteps do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:order) { shopify_fixture('order_details_open')['order'] }
  let(:currency) { order['currencyCode'] }
  let(:total) { order.dig('totalPriceSet', 'shopMoney', 'amount') }
  let(:lines) { order.dig('lineItems', 'nodes') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, custom_attributes: tied) }
  let(:tied) { { 'shopify_order_id' => order['id'], 'shopify_order_number' => order['name'] } }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_const('Inclamo::Shopify::Actions::Cancel::POLL', 0)
    stub_shopify(:order_details, data: { order: order })
  end

  def macro_with(*names, name: 'Refund and close')
    actions = names.map do |step|
      params = { 'send_message' => ['Sorry, we refunded you.'], 'add_label' => ['refunded'], 'add_private_note' => ['Macro started'] }.fetch(step, [])
      { 'action_name' => step, 'action_params' => params }
    end
    create(:macro, account: account, name: name, created_by: admin, visibility: :global, actions: actions)
  end

  def run(macro, user = admin)
    Macros::ExecutionService.new(macro, conversation, user).perform
  end

  def mutation_requests(name)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^mutation #{name}\b/) && (!block_given? || yield(body['variables']))
    end
  end

  def query_requests(name)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^query #{name}\b/) && (!block_given? || yield(body['variables']))
    end
  end

  def notes
    conversation.messages.where(private: true).pluck(:content)
  end

  def sent
    conversation.messages.where(private: false, message_type: :outgoing).pluck(:content)
  end

  def stub_suggestion(amount: total, shipping: '0.0')
    stub_shopify(:refund_suggestion, data: { order: { id: order['id'], name: order['name'], currencyCode: currency, suggestedRefund: {
                   amountSet: { shopMoney: { amount: amount, currencyCode: currency } },
                   maximumRefundableSet: { shopMoney: { amount: total, currencyCode: currency } },
                   shipping: { amountSet: { shopMoney: { amount: shipping, currencyCode: currency } }, maximumRefundableSet: { shopMoney: { amount: shipping, currencyCode: currency } } },
                   refundLineItems: lines.map { |line| { lineItem: { id: line['id'] }, quantity: line['quantity'], restockType: 'NO_RESTOCK' } },
                   suggestedTransactions: [{ gateway: 'manual', formattedGateway: 'Manual', kind: 'SUGGESTED_REFUND',
                                             amountSet: { shopMoney: { amount: amount, currencyCode: currency } },
                                             maximumRefundableSet: { shopMoney: { amount: total, currencyCode: currency } },
                                             parentTransaction: { id: 'gid://shopify/OrderTransaction/1' } }]
                 } } })
  end

  def stub_refund(amount, errors: [])
    stub_shopify(:refund_create, data: { refundCreate: { refund: errors.empty? ? { id: 'gid://shopify/Refund/1', totalRefundedSet: { shopMoney: { amount: amount, currencyCode: currency } } } : nil,
                                                         userErrors: errors } })
  end

  def stub_cancel
    stub_shopify(:order_cancel, data: { orderCancel: { job: { id: 'gid://shopify/Job/1', done: false }, orderCancelUserErrors: [] } })
    stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: true } })
    stub_shopify(:order_details_limited, data: { order: order.merge('cancelledAt' => '2026-11-06T12:00:00Z') })
  end

  def stub_replacement
    draft = 'gid://shopify/DraftOrder/77'
    stub_shopify(:replacement_draft_create, data: { draftOrderCreateFromOrder: { draftOrder: { id: draft, name: '#D7', lineItems: {
                   nodes: lines.each_with_index.map do |line, index|
                     { id: "gid://shopify/DraftOrderLineItem/#{index}", title: line['title'], variantTitle: line['variantTitle'], sku: line['sku'],
                       quantity: line['quantity'], custom: false, variant: { id: "gid://shopify/ProductVariant/#{index + 1}" } }
                   end
                 } }, userErrors: [] } })
    stub_shopify(:replacement_draft_update, data: { draftOrderUpdate: { draftOrder: { id: draft, totalPriceSet: { shopMoney: { amount: '0.0', currencyCode: currency } } }, userErrors: [] } })
    stub_shopify(:replacement_draft_complete, data: { draftOrderComplete: { draftOrder: { id: draft, order: { id: 'gid://shopify/Order/9', name: '#1050' } }, userErrors: [] } })
  end

  describe 'the four steps' do
    it 'refunds the order in full: everything refundable, nothing restocked, the customer notified' do
      stub_suggestion
      stub_refund(total)

      run(macro_with('inclamo_refund_full', 'send_message', 'resolve_conversation'))

      expect(mutation_requests('refund_create') do |variables|
        input = variables['input']
        input['notify'] == true && input['transactions'].sum { |transaction| transaction['amount'].to_d } == total.to_d &&
          input['refundLineItems'].pluck('restockType').uniq == ['NO_RESTOCK'] && variables['key'].start_with?('macro-')
      end).to have_been_made.once
      expect(Inclamo::OrderAction.last).to have_attributes(action: 'refund', outcome: 'accepted', user_id: admin.id)
      expect(notes).to eq(["Refunded #{total} #{currency} on order #1001."])
      expect(sent).to eq(['Sorry, we refunded you.'])
      expect(conversation.reload.status).to eq('resolved')
    end

    it 'refunds the shipping cost alone, no item' do
      stub_suggestion(amount: '50.0', shipping: '50.0')
      stub_refund('50.0')

      run(macro_with('inclamo_refund_shipping'))

      expect(query_requests('refund_suggestion') do |variables|
        variables['refundShipping'] == true && variables['suggestFullRefund'] == false && variables['refundLineItems'].nil?
      end).to have_been_made.at_least_once
      expect(mutation_requests('refund_create') do |variables|
        input = variables['input']
        input['shipping'] == { 'fullRefund' => true } && !input.key?('refundLineItems') && input['notify'] == true &&
          input['transactions'].pluck('amount') == ['50.0']
      end).to have_been_made.once
      expect(notes).to eq(["Refunded 50.0 #{currency} on order #1001."])
    end

    it 'does not refund the shipping of an order whose shipping was free or already refunded' do
      stub_suggestion(amount: '0.0', shipping: '0.0')

      run(macro_with('inclamo_refund_shipping', 'send_message'))

      expect(mutation_requests('refund_create')).not_to have_been_made
      expect(notes.last).to include('no shipping cost left to refund')
      expect(sent).to be_empty
    end

    it 'cancels the order at the customer request, refunded, restocked, the customer notified' do
      stub_cancel

      run(macro_with('inclamo_cancel_order', 'send_message'))

      expect(mutation_requests('order_cancel') do |variables|
        variables['reason'] == 'CUSTOMER' && variables['restock'] == true && variables['notifyCustomer'] == true &&
          variables['refundMethod'] == { 'originalPaymentMethodsRefund' => true }
      end).to have_been_made.once
      expect(Inclamo::OrderAction.last).to have_attributes(action: 'cancel', outcome: 'accepted')
      expect(sent).to eq(['Sorry, we refunded you.'])
    end

    it 'sends a free replacement with every item of the order' do
      stub_replacement

      run(macro_with('inclamo_replacement'))

      expect(mutation_requests('replacement_draft_update') do |variables|
        variables.dig('input', 'lineItems') == lines.each_index.map { |index| { 'variantId' => "gid://shopify/ProductVariant/#{index + 1}", 'quantity' => lines[index]['quantity'] } }
      end).to have_been_made.once
      expect(mutation_requests('replacement_draft_complete')).to have_been_made.once
      expect(notes).to eq(['Created replacement order #1050 for order #1001, free of charge.'])
    end
  end

  describe 'a step that is not done stops the macro' do
    it 'stops when no order is tied, without asking the store' do
      conversation.update!(custom_attributes: {})

      run(macro_with('inclamo_refund_full', 'send_message', 'resolve_conversation'))

      expect(WebMock).not_to have_requested(:any, /myshopify/)
      expect(sent).to be_empty
      expect(conversation.reload.status).to eq('open')
      expect(notes).to eq(['Macro "Refund and close" stopped at the step "Refund the order in full": no order is tied to this conversation, ' \
                           'so there was no order to act on. The steps after it did not run.'])
    end

    it 'stops for an agent without the order-actions role, and records the attempt' do
      run(macro_with('inclamo_refund_full', 'send_message', 'resolve_conversation'), agent)

      expect(WebMock).not_to have_requested(:any, /myshopify/)
      expect(Inclamo::OrderAction.last).to have_attributes(outcome: 'refused', refusal: 'not_allowed', user_id: agent.id)
      expect(sent).to be_empty
      expect(conversation.reload.status).to eq('open')
      expect(notes.last).to include('you may not act on orders')
    end

    it 'lets an agent holding the role run it' do
      Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), granted_by: admin)
      stub_suggestion
      stub_refund(total)

      run(macro_with('inclamo_refund_full', 'send_message'), agent)

      expect(sent).to eq(['Sorry, we refunded you.'])
    end

    it 'stops when the app of the store lacks a scope, naming it' do
      record.update!(scopes: %w[read_customers read_orders])

      run(macro_with('inclamo_replacement', 'send_message'))

      expect(WebMock).not_to have_requested(:any, /myshopify/)
      expect(notes.last).to include('lacks access: write_orders, write_draft_orders, read_products')
      expect(sent).to be_empty
    end

    it 'stops when the store refuses, giving its reason' do
      stub_suggestion
      stub_refund(total, errors: [{ field: ['transactions'], message: 'Refund amount exceeds the amount available' }])

      run(macro_with('inclamo_refund_full', 'send_message', 'resolve_conversation'))

      expect(Inclamo::OrderAction.last).to have_attributes(outcome: 'refused', refusal: 'store_refused')
      expect(notes.last).to include('the store refused: Refund amount exceeds the amount available')
      expect(sent).to be_empty
      expect(conversation.reload.status).to eq('open')
    end

    it 'stops on an order with nothing left to refund, as for a macro run a second time' do
      refunded = order.merge('totalRefundedSet' => order['totalReceivedSet'], 'refundable' => false)
      stub_shopify(:order_details, data: { order: refunded })

      run(macro_with('inclamo_refund_full', 'send_message'))

      expect(mutation_requests('refund_create')).not_to have_been_made
      expect(notes.last).to include('nothing left to refund')
      expect(sent).to be_empty
    end

    it 'stops while the store is still cancelling, so the confirmation is not sent too early' do
      stub_const('Inclamo::Shopify::Actions::Cancel::WAIT', 0)
      stub_shopify(:order_cancel, data: { orderCancel: { job: { id: 'gid://shopify/Job/1', done: false }, orderCancelUserErrors: [] } })
      stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: false } })

      run(macro_with('inclamo_cancel_order', 'send_message'))

      expect(Inclamo::OrderAction.last.outcome).to eq('running')
      expect(notes.last).to include('has not finished the cancellation yet')
      expect(sent).to be_empty
    end

    it 'stops on an error of our own instead of letting Chatwoot go on' do
      allow(Inclamo::Shopify::OrderActionRunner).to receive(:new).and_raise(NoMethodError, 'broken')

      run(macro_with('inclamo_refund_full', 'send_message'))

      expect(notes.last).to include('stopped at the step "Refund the order in full": it could not be done.')
      expect(sent).to be_empty
    end

    it 'keeps the steps before it done' do
      conversation.update!(custom_attributes: {})

      run(macro_with('add_label', 'add_private_note', 'inclamo_refund_full', 'send_message'))

      expect(conversation.reload.label_list).to eq(['refunded'])
      expect(notes.first).to eq('Macro started')
      expect(sent).to be_empty
    end

    it 'leaves Chatwoot steps as they were: an error is swallowed and the next step runs' do
      macro = macro_with('add_label', 'send_message')
      service = Macros::ExecutionService.new(macro, conversation, admin)
      allow(service).to receive(:add_label).and_raise(StandardError, 'label service down')

      service.perform

      expect(sent).to eq(['Sorry, we refunded you.'])
    end

    it 'runs a macro without order steps as before' do
      run(macro_with('add_label', 'send_message', 'resolve_conversation'))

      expect(sent).to eq(['Sorry, we refunded you.'])
      expect(conversation.reload.status).to eq('resolved')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'the record' do
    it 'names the macro the step ran in' do
      stub_suggestion
      stub_refund(total)
      macro = macro_with('inclamo_refund_full')

      run(macro)

      expect(Inclamo::OrderAction.last.macro_id).to eq(macro.id)
      expect(Inclamo::OrderAction.last.as_json).to include(macro_id: macro.id, action: 'refund', order_number: '#1001')
    end

    it 'names no macro for an action from the panel' do
      runner = Inclamo::Shopify::OrderActionRunner.new(account: account, account_user: AccountUser.find_by(account: account, user: admin), conversation: conversation)
      stub_cancel

      runner.perform(action: 'cancel', action_id: 'action-cancel-0001', order_id: order['id'], params: { 'reason' => 'customer', 'refund' => true })

      expect(Inclamo::OrderAction.last.macro_id).to be_nil
    end
  end
end
