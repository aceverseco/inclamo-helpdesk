# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderActionRunner, 'new order' do
  let(:record) { create(:inclamo_shopify_connection, shop_currency: 'UAH') }
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:customer) { shopify_fixture('customer_orders')['customer'] }
  let(:runner) { runner_for(admin) }
  let(:created) { shopify_fixture('new_order_create').dig('draftOrderCreate', 'draftOrder') }
  let(:lines) { [{ 'variant_id' => 'gid://shopify/ProductVariant/1', 'quantity' => 1 }, { 'variant_id' => 'gid://shopify/ProductVariant/2', 'quantity' => 2 }] }
  let(:order_params) { { 'lines' => lines, 'discount' => { 'type' => 'percentage', 'value' => '10' }, 'shipping' => '5.00', 'delivery' => 'email' } }

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    Inclamo::Shopify::CustomerMatcher.remember!(contact, customer['id'])
    stub_shopify(:customer_orders, data: { customer: customer })
    stub_shopify_fixture(:new_order_calculate, 'new_order_calculate')
    stub_shopify_fixture(:new_order_create, 'new_order_create')
    stub_shopify_fixture(:new_order_invoice_send, 'new_order_invoice_send')
  end

  def runner_for(user)
    described_class.new(account: account, account_user: AccountUser.find_by(account: account, user: user), conversation: conversation)
  end

  def operation_requests(name)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^(query|mutation) #{name}\b/) && (!block_given? || yield(body['variables']))
    end
  end

  def notes
    conversation.messages.where(private: true).pluck(:content)
  end

  def create_order(params = order_params, id: 'action-new-order-0001', note: nil, as: runner)
    as.perform(action: 'new_order', action_id: id, order_id: nil, params: params, extra: { note: note })
  end

  # The store keeps throttling the operation until the time limit: it is not executed.
  def stub_throttled(operation)
    body = { errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }],
             extensions: { cost: { requestedQueryCost: 1000, throttleStatus: { currentlyAvailable: 0, restoreRate: 50 } } } }
    stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].match?(/^(query|mutation) #{operation}\b/) }
                                            .to_return(status: 200, body: body.to_json, headers: ShopifyStubs::JSON_HEADERS)
  end

  # The customer's drafts as the lookup of a lost attempt pages through them.
  def stub_found_drafts(*pages)
    pages.each_with_index do |nodes, index|
      cursor = index.zero? ? nil : "page-#{index}"
      page = { nodes: nodes, pageInfo: { hasNextPage: index < pages.size - 1, endCursor: "page-#{index + 1}" } }
      stub_request(:post, shopify_graphql_url).with do |r|
        body = JSON.parse(r.body)
        body['query'].match?(/^query new_order_find_draft\b/) && body.dig('variables', 'after') == cursor
      end.to_return(status: 200, body: { data: { draftOrders: page } }.to_json, headers: ShopifyStubs::JSON_HEADERS)
    end
  end

  def drafts(marker: nil)
    nodes = shopify_fixture('awaiting_payment').dig('draftOrders', 'nodes')
    marker ? nodes.first(2) + [nodes.last.merge('marker' => { 'value' => marker }, 'invoiceSentAt' => nil)] : nodes
  end

  def stub_lost(operation)
    stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].match?(/^(query|mutation) #{operation}\b/) }.to_timeout
  end

  describe 'preview' do
    it 'shows the store calculation and creates nothing' do
      preview = runner.new_order_preview(params: order_params)

      expect(preview).to include(currency: 'UAH', total: { amount: '2062.27', currency: 'UAH' }, discount: { amount: '228.58', currency: 'UAH' },
                                 shipping: { amount: '5.0', currency: 'UAH' }, subtotal: { amount: '2285.85', currency: 'UAH' })
      expect(preview[:lines].pluck(:title, :quantity)).to eq([['The Minimal Snowboard', 1], ['The Complete Snowboard - Ice', 2]])
      expect(operation_requests('new_order_calculate') do |variables|
        input = variables['input']
        input['purchasingEntity'] == { 'customerId' => customer['id'] } && input['useCustomerDefaultAddress'] == true &&
          input['appliedDiscount'].slice('valueType', 'value') == { 'valueType' => 'PERCENTAGE', 'value' => 10.0 } &&
          input.dig('shippingLine', 'priceWithCurrency') == { 'amount' => '5.00', 'currencyCode' => 'UAH' } && !input.key?('tags')
      end).to have_been_made.once
      expect(operation_requests('new_order_create')).not_to have_been_made
      expect(Inclamo::OrderAction.count).to eq(0)
    end

    it 'gives the store reason when it refuses the calculation' do
      stub_shopify_fixture(:new_order_calculate, 'new_order_calculate_refused')

      expect { runner.new_order_preview(params: order_params) }
        .to raise_error(Inclamo::Shopify::Actions::Refused, 'Quantity must be greater than or equal to 1')
    end

    it 'checks the lines and the discount before asking the store' do
      refusal = lambda do |params|
        runner.new_order_preview(params: order_params.merge(params))
      rescue Inclamo::Shopify::Actions::Refused => e
        e.code
      end

      expect(refusal.call('lines' => [])).to eq('no_items')
      expect(refusal.call('lines' => [{ 'variant_id' => 'gid://shopify/Product/1', 'quantity' => 1 }])).to eq('invalid_item')
      expect(refusal.call('lines' => [{ 'variant_id' => 'gid://shopify/ProductVariant/1', 'quantity' => 0 }])).to eq('invalid_quantity')
      expect(refusal.call('discount' => { 'type' => 'percentage', 'value' => '120' })).to eq('invalid_discount')
      expect(refusal.call('discount' => { 'type' => 'free', 'value' => '1' })).to eq('invalid_discount')
      expect(refusal.call('shipping' => '-5')).to eq('invalid_shipping')
      expect(operation_requests('new_order_calculate')).not_to have_been_made
    end

    it 'adds up the quantities of a variant chosen twice and leaves out no discount and no shipping' do
      runner.new_order_preview(params: { 'lines' => [lines.first, lines.first] })

      expect(operation_requests('new_order_calculate') do |variables|
        variables['input']['lineItems'] == [{ 'variantId' => 'gid://shopify/ProductVariant/1', 'quantity' => 2 }] &&
          !variables['input'].key?('appliedDiscount') && !variables['input'].key?('shippingLine')
      end).to have_been_made.once
    end

    it 'takes an amount discount in the shop currency' do
      runner.new_order_preview(params: order_params.merge('discount' => { 'type' => 'amount', 'value' => '7.50' }))

      expect(operation_requests('new_order_calculate') do |variables|
        variables.dig('input', 'appliedDiscount') == { 'valueType' => 'FIXED_AMOUNT', 'value' => 7.5, 'title' => 'Discount',
                                                       'amountWithCurrency' => { 'amount' => '7.50', 'currencyCode' => 'UAH' } }
      end).to have_been_made.once
    end
  end

  describe 'order again' do
    let(:source) { shopify_fixture('new_order_from_order')['order'] }

    it 'starts from the items and quantities of an order of the customer, naming what is no longer sold' do
      stub_shopify(:new_order_from_order, data: { order: source.merge('customer' => { 'id' => customer['id'] }) })

      prefill = runner.new_order_prefill(order_id: source['id'])

      expect(prefill[:order_number]).to eq(source['name'])
      expect(prefill[:lines].map { |line| [line[:product][:title], line[:quantity]] }).to eq([['The Minimal Snowboard', 1], ['The Complete Snowboard', 2]])
      expect(prefill[:lines].first[:variant]).to include(id: a_string_starting_with('gid://shopify/ProductVariant/'), available_for_sale: true,
                                                         price: { amount: '885.95', currency: 'UAH' })
      expect(prefill[:skipped]).to eq([{ title: 'The Archived Snowboard', quantity: 1 }])
    end

    it 'adds only what the catalogue search would offer, at the quantity still in the order, one line per variant' do
      first, second, archived = source.dig('lineItems', 'nodes')
      gift = first.deep_merge('name' => 'Gift Card', 'variant' => { 'id' => 'gid://shopify/ProductVariant/501', 'product' => { 'isGiftCard' => true } })
      sold_out = first.deep_merge('name' => 'Sold Out Board', 'variant' => { 'id' => 'gid://shopify/ProductVariant/502', 'availableForSale' => false })
      refunded = second.merge('name' => 'Refunded Board', 'quantity' => 3, 'currentQuantity' => 0)
      partly = second.merge('quantity' => 3, 'currentQuantity' => 1)
      again = first.merge('quantity' => 2, 'currentQuantity' => 2)
      nodes = [first, partly, gift, sold_out, refunded, again, archived]
      stub_shopify(:new_order_from_order, data: { order: source.merge('customer' => { 'id' => customer['id'] }, 'lineItems' => { 'nodes' => nodes }) })

      prefill = runner.new_order_prefill(order_id: source['id'])

      expect(prefill[:lines].map { |line| [line[:variant][:id], line[:quantity]] }).to eq([[first.dig('variant', 'id'), 3], [second.dig('variant', 'id'), 1]])
      expect(prefill[:skipped]).to eq([{ title: 'Gift Card', quantity: 1 }, { title: 'Sold Out Board', quantity: 1 }, { title: 'The Archived Snowboard', quantity: 1 }])
    end

    it 'refuses an order of another customer' do
      stub_shopify(:new_order_from_order, data: { order: source.merge('customer' => { 'id' => 'gid://shopify/Customer/1' }) })

      expect { runner.new_order_prefill(order_id: source['id']) }.to raise_error(Inclamo::Shopify::Actions::Refused, 'not_customers_order')
    end
  end

  describe 'creating' do
    it 'creates an unpaid draft for the customer with the lines, discount, shipping, note, tag and marker, and emails the invoice' do
      result = create_order(note: 'Gift wrap, please')

      expect(result).to have_attributes(outcome: 'accepted', order_id: nil)
      expect(operation_requests('new_order_create') do |variables|
        input = variables['input']
        input['purchasingEntity'] == { 'customerId' => customer['id'] } && input['useCustomerDefaultAddress'] == true &&
          input['lineItems'].size == 2 && input['tags'] == ['inclamo-helpdesk'] && input['note'] == 'Gift wrap, please' &&
          input['metafields'] == [{ 'namespace' => 'inclamo', 'key' => 'action_id', 'type' => 'single_line_text_field', 'value' => 'action-new-order-0001' }] &&
          input['appliedDiscount']['valueType'] == 'PERCENTAGE' && input.dig('shippingLine', 'priceWithCurrency', 'amount') == '5.00'
      end).to have_been_made.once
      expect(operation_requests('new_order_invoice_send') { |variables| variables['id'] == created['id'] }).to have_been_made.once
      expect(operation_requests('replacement_draft_complete')).not_to have_been_made
      expect(result.as_json[:result]).to include('draft_name' => created['name'], 'invoice_sent' => true, 'delivery' => 'email',
                                                 'total' => { 'amount' => '2062.27', 'currency' => 'UAH' }, 'invoice_url' => created['invoiceUrl'])
    end

    it 'does not send the invoice when the link goes into the reply' do
      result = create_order(order_params.merge('delivery' => 'reply'))

      expect(result.outcome).to eq('accepted')
      expect(result.progress).to include('invoice_sent' => false, 'invoice_url' => created['invoiceUrl'])
      expect(operation_requests('new_order_invoice_send')).not_to have_been_made
    end

    it 'does not email a customer without an email, and creates nothing then' do
      stub_shopify(:customer_orders, data: { customer: customer.merge('defaultEmailAddress' => nil) })

      expect(create_order.refusal).to eq('no_email')
      expect(create_order(order_params.merge('delivery' => 'reply'), id: 'action-new-order-0002').outcome).to eq('accepted')
      expect(operation_requests('new_order_create')).to have_been_made.once
      expect(operation_requests('new_order_invoice_send')).not_to have_been_made
    end

    it 'needs a way to deliver the link' do
      expect(create_order(order_params.merge('delivery' => 'sms')).refusal).to eq('invalid_delivery')
    end

    it 'needs a customer matched to the conversation' do
      Inclamo::Shopify::CustomerMatcher.remember!(contact, nil)
      contact.update!(email: nil, phone_number: nil)

      expect(create_order.refusal).to eq('no_customer')
      expect(operation_requests('new_order_create')).not_to have_been_made
    end

    it 'is refused to an agent without the role, without the scopes and in the limited mode, with no store call' do
      create(:inbox_member, inbox: conversation.inbox, user: agent)
      expect(create_order(as: runner_for(agent)).refusal).to eq('not_allowed')

      record.update!(scopes: %w[read_customers read_orders write_orders read_products])
      expect(create_order(id: 'action-new-order-0002').refusal).to eq('missing_scope')
      expect(record.missing_scopes_for('new_order')).to eq(%w[write_draft_orders])

      record.update!(scopes: %w[read_customers read_orders write_draft_orders read_products], customer_data_mode: 'limited')
      expect(create_order(id: 'action-new-order-0003', as: runner_for(admin)).refusal).to eq('customer_data_hidden')
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url)
    end

    it 'shows the store reason when it refuses the order, and nothing is created' do
      stub_shopify(:new_order_create, data: { draftOrderCreate: { draftOrder: nil, userErrors: [{ field: nil, message: 'Product with ID 1 is no longer available.' }] } })

      result = create_order

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'Product with ID 1 is no longer available.')
      expect(operation_requests('new_order_invoice_send')).not_to have_been_made
      expect(notes).to be_empty
    end

    it 'removes the draft when the store refuses to send the invoice' do
      stub_shopify_fixture(:new_order_invoice_send, 'new_order_invoice_send_no_email')
      stub_shopify(:replacement_draft_delete, data: { draftOrderDelete: { deletedId: created['id'], userErrors: [] } })

      result = create_order

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: "To can't be blank")
      expect(operation_requests('replacement_draft_delete') { |variables| variables['id'] == created['id'] }).to have_been_made.once
      expect(notes).to be_empty
    end

    it 'removes the draft when the invoice cannot be sent because the store keeps throttling, so that a retry makes no second order' do
      stub_throttled(:new_order_invoice_send)
      stub_shopify(:replacement_draft_delete, data: { draftOrderDelete: { deletedId: created['id'], userErrors: [] } })

      result = create_order

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_unreachable', store_message: 'throttled')
      expect(operation_requests('replacement_draft_delete') { |variables| variables['id'] == created['id'] }).to have_been_made.once
      expect(notes).to be_empty
    end

    it 'names the draft with a link when the invoice failed and the draft could not be removed' do
      stub_throttled(:new_order_invoice_send)
      stub_throttled(:replacement_draft_delete)

      result = create_order

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_unreachable')
      expect(result.store_message).to include(created['name'], "https://admin.shopify.com/store/example-store/draft_orders/#{created['legacyResourceId']}")
    end

    it 'keeps the draft when the answer to the invoice was lost: the store may have sent it' do
      stub_lost(:new_order_invoice_send)

      result = create_order

      expect(result.outcome).to eq('unknown')
      expect(operation_requests('replacement_draft_delete')).not_to have_been_made
      expect(result.progress).to include('draft_id' => created['id'], 'invoice_asked' => true, 'invoice_sent' => false)
    end

    it 'records the draft, total and delivery, not the note, and leaves a private note without customer data' do
      result = create_order(note: 'Leave at the door of flat 12')

      expect(result.params).to eq(order_params)
      expect(result.params.to_json).not_to include('flat 12')
      expect(result.progress.to_json).not_to include('flat 12', 'maya', 'Example Street')
      expect(notes).to eq(["Created order #{created['name']} for 2062.27 UAH, awaiting payment. The store emailed its invoice to the customer."])
      expect(conversation.messages.where(private: true).last.sender).to eq(admin)
    end

    it 'says in the note that the link went into the reply' do
      create_order(order_params.merge('delivery' => 'reply'))

      expect(notes).to eq(["Created order #{created['name']} for 2062.27 UAH, awaiting payment. The payment link was put into the reply."])
    end

    it 'drops the cached orders of the account after the action' do
      expect(Inclamo::Shopify::OrderReader).to receive(:forget!).with(account.id).and_call_original
      create_order
    end
  end

  describe 'an attempt whose answer was lost' do
    let(:lost_create) { stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation new_order_create') }.to_timeout }

    def lose_first_attempt
      lost_create
      first = create_order
      expect(first.outcome).to eq('unknown')
      remove_request_stub(lost_create)
      first
    end

    it 'stays unknown while the store search may not show the draft yet' do
      lose_first_attempt

      again = create_order

      expect(again.outcome).to eq('unknown')
      expect(operation_requests('new_order_find_draft')).not_to have_been_made
      expect(operation_requests('new_order_create')).to have_been_made.once
    end

    it 'is finished from the draft that carries its marker, without a second draft' do
      first = lose_first_attempt
      mine = drafts(marker: 'action-new-order-0001').last
      stub_found_drafts(drafts(marker: 'action-new-order-0001'))

      again = travel_to(31.seconds.from_now) { create_order }

      expect(again).to have_attributes(outcome: 'accepted')
      expect(again.progress).to include('draft_id' => mine['id'], 'draft_name' => mine['name'], 'invoice_sent' => true)
      around = "created_at:>='#{(first.created_at - 5.minutes).utc.iso8601}' created_at:<='#{(first.created_at + 10.minutes).utc.iso8601}'"
      expect(operation_requests('new_order_find_draft') do |variables|
        variables['query'] == "customer_id:#{customer['id'].split('/').last} tag:inclamo-helpdesk #{around}" && variables['first'] == 50
      end).to have_been_made.once
      expect(operation_requests('new_order_create')).to have_been_made.once
      expect(notes.size).to eq(1)
    end

    it 'is refused as not created when no draft carries its marker' do
      lose_first_attempt
      stub_found_drafts(drafts)

      again = travel_to(31.seconds.from_now) { create_order }

      expect(again).to have_attributes(outcome: 'refused', refusal: 'not_created')
      expect(operation_requests('new_order_create')).to have_been_made.once
    end

    it 'is not made again by a panel read while the first request has not reached the store yet' do
      record = Inclamo::OrderAction.create!(account: account, conversation: conversation, user: admin, action_id: 'action-new-order-0042',
                                            action: 'new_order', params: order_params, outcome: 'pending')

      runner.settle_open!
      expect(record.reload.outcome).to eq('pending')

      # A request that never asked the store, and ended: nothing was created.
      travel_to((Inclamo::Shopify::OrderActionRunner::LEASE + 1.second).from_now) { runner.settle_open! }
      expect(record.reload).to have_attributes(outcome: 'refused', refusal: 'not_created')
      expect(operation_requests('new_order_create')).not_to have_been_made
    end

    it 'is settled when the panel is read' do
      lose_first_attempt
      stub_found_drafts(drafts)

      travel_to(31.seconds.from_now) { runner.settle_open! }

      expect(Inclamo::OrderAction.last).to have_attributes(outcome: 'refused', refusal: 'not_created')
    end

    it 'finds the draft past the first page of the customer drafts made around the attempt' do
      lose_first_attempt
      others = Array.new(50) { |index| drafts.first.merge('id' => "gid://shopify/DraftOrder/#{9000 + index}", 'marker' => { 'value' => "other-action-#{index}" }) }
      stub_found_drafts(others, drafts(marker: 'action-new-order-0001'))

      travel_to(31.seconds.from_now) { runner.settle_open! }

      expect(Inclamo::OrderAction.last).to have_attributes(outcome: 'accepted')
      expect(Inclamo::OrderAction.last.progress['draft_name']).to eq(drafts.last['name'])
      expect(operation_requests('new_order_find_draft')).to have_been_made.twice
      expect(operation_requests('new_order_create')).to have_been_made.once
    end

    it 'stays unknown when the customer has more drafts around the attempt than are looked through' do
      stub_const('Inclamo::Shopify::Actions::NewOrder::LOOK_PAGES', 1)
      lose_first_attempt
      stub_found_drafts(drafts, drafts)

      travel_to(31.seconds.from_now) { runner.settle_open! }

      expect(Inclamo::OrderAction.last).to have_attributes(outcome: 'unknown', refusal: nil)
    end

    it 'stays unknown, not refused, when the store cannot be read to look for the draft' do
      first = lose_first_attempt
      stub_throttled(:new_order_find_draft)

      again = travel_to(31.seconds.from_now) { create_order }
      expect(again).to have_attributes(id: first.id, outcome: 'unknown', refusal: nil)

      travel_to(32.seconds.from_now) { runner.settle_open! }
      expect(first.reload).to have_attributes(outcome: 'unknown', refusal: nil, completed_at: nil)

      stub_shopify(:new_order_find_draft, errors: [{ message: 'Internal error. Looks like something went wrong on our end.' }])
      travel_to(33.seconds.from_now) { runner.settle_open! }
      expect(first.reload).to have_attributes(outcome: 'unknown', refusal: nil)
      expect(operation_requests('new_order_create')).to have_been_made.once
    end

    it 'stays unknown when the store cannot be read to learn whether the invoice went out' do
      stub_lost(:new_order_invoice_send)
      first = create_order
      stub_throttled(:new_order_draft)

      again = create_order
      runner.settle_open!

      expect(again).to have_attributes(id: first.id, outcome: 'unknown', refusal: nil)
      expect(first.reload.outcome).to eq('unknown')
      expect(operation_requests('new_order_invoice_send')).to have_been_made.once
    end

    it 'is not emailed twice when the confirmation is sent again after the answer to the invoice was lost' do
      stub_lost(:new_order_invoice_send)
      first = create_order
      stub_shopify(:new_order_draft, data: { draftOrder: shopify_fixture('new_order_draft_sent')['draftOrder'].merge('id' => created['id']) })

      again = create_order

      expect(again).to have_attributes(id: first.id, outcome: 'accepted')
      expect(operation_requests('new_order_invoice_send')).to have_been_made.once
      expect(notes).to eq(["Created order #{created['name']} for 2062.27 UAH, awaiting payment. The store emailed its invoice to the customer."])
    end

    it 'sends nothing on a panel read while the first request is still asking the store for the invoice' do
      in_flight = Inclamo::OrderAction.create!(account: account, conversation: conversation, user: admin, action_id: 'action-new-order-0043', action: 'new_order',
                                               params: order_params, outcome: 'pending',
                                               progress: { 'attempted' => true, 'customer_id' => customer['id'], 'draft_id' => created['id'],
                                                           'draft_name' => created['name'], 'invoice_sent' => false, 'invoice_asked' => true })

      runner.settle_open!

      expect(in_flight.reload).to have_attributes(outcome: 'pending')
      expect(operation_requests('new_order_invoice_send')).not_to have_been_made
      expect(notes).to be_empty
    end

    it 'reads on a panel read whether the invoice went out after its answer was lost, and never sends it' do
      stub_lost(:new_order_invoice_send)
      first = create_order
      stub_shopify(:new_order_draft, data: { draftOrder: shopify_fixture('new_order_draft_open')['draftOrder'].merge('id' => created['id']) })

      runner.settle_open!

      expect(first.reload.outcome).to eq('accepted')
      expect(operation_requests('new_order_invoice_send')).to have_been_made.once
      expect(notes).to eq(["Created order #{created['name']} for 2062.27 UAH, awaiting payment. " \
                           "The payment link was not sent yet: it is under Awaiting payment in the conversation's Orders section."])
    end

    it 'does not say the link went into the reply when a panel read found the order: no dialog put it there' do
      nodes = drafts(marker: 'action-new-order-0002')
      stub_found_drafts(nodes)
      lost_create
      create_order(order_params.merge('delivery' => 'reply'), id: 'action-new-order-0002')
      remove_request_stub(lost_create)

      travel_to(31.seconds.from_now) { runner.settle_open! }

      reply_order = Inclamo::OrderAction.find_by(action_id: 'action-new-order-0002')
      expect(reply_order.outcome).to eq('accepted')
      expect(notes).to eq(["Created order #{nodes.last['name']} for #{nodes.last.dig('totalPriceSet', 'shopMoney', 'amount')} UAH, awaiting payment. " \
                           "The payment link was not sent yet: it is under Awaiting payment in the conversation's Orders section."])
    end
  end
end
