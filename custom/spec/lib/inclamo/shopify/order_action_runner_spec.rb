# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderActionRunner do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:open_order) { shopify_fixture('order_details_open')['order'] }
  let(:order_id) { open_order['id'] }
  let(:address) { { 'first_name' => 'Maya', 'last_name' => 'Example', 'address1' => '2 Example Avenue', 'city' => 'Springfield', 'province_code' => 'IL', 'zip' => '62702', 'country_code' => 'US' } }

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_const('Inclamo::Shopify::Actions::Cancel::POLL', 0)
  end

  def member(user)
    AccountUser.find_by(account: account, user: user)
  end

  def runner(user = admin)
    described_class.new(account: account, account_user: member(user), conversation: conversation)
  end

  def cancel(user = admin, id: 'action-cancel-0001', params: { 'reason' => 'customer', 'refund' => true, 'restock' => true })
    runner(user).perform(action: 'cancel', action_id: id, order_id: order_id, params: params)
  end

  def stub_order(node = open_order)
    stub_shopify(:order_details, data: { order: node })
  end

  def stub_cancel(done: true, errors: [])
    stub_shopify(:order_cancel, data: { orderCancel: { job: errors.empty? ? { id: 'gid://shopify/Job/1', done: false } : nil, orderCancelUserErrors: errors } })
    stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: done } })
    stub_shopify(:order_details_limited, data: { order: open_order.merge('cancelledAt' => (done ? '2026-11-05T12:00:00Z' : nil)) })
  end

  def private_notes
    conversation.messages.where(private: true)
  end

  describe 'who may act' do
    it 'refuses an agent without the role, without calling the store, and records the attempt' do
      result = cancel(agent)

      expect(result).to have_attributes(outcome: 'refused', refusal: 'not_allowed')
      expect(result).to be_persisted
      expect(WebMock).not_to have_requested(:any, /myshopify/)
      expect(private_notes).to be_empty
    end

    it 'lets an agent holding the role act' do
      Inclamo::OrderRole.create!(account_user: member(agent), granted_by: admin)
      stub_order
      stub_cancel

      expect(cancel(agent).outcome).to eq('accepted')
    end

    it 'refuses when the role was taken away after the dialog opened' do
      role = Inclamo::OrderRole.create!(account_user: member(agent), granted_by: admin)
      role.destroy!

      expect(cancel(agent)).to have_attributes(outcome: 'refused', refusal: 'not_allowed')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'refuses an action whose scope the app lacks, without calling the store' do
      record.update!(scopes: %w[read_customers read_orders])

      expect(cancel).to have_attributes(outcome: 'refused', refusal: 'missing_scope')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'refuses while the connection is broken' do
      record.update!(status: 'broken')

      expect(cancel.refusal).to eq('connection_broken')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'cancelling' do
    it 'cancels, records the action and leaves a private note by the agent who acted' do
      stub_order
      cancellation = stub_cancel

      result = cancel

      expect(result).to have_attributes(outcome: 'accepted', order_number: '#1001', params: { 'reason' => 'customer', 'refund' => true, 'restock' => true })
      expect(cancellation.with { |r| JSON.parse(r.body)['variables'].slice('reason', 'restock', 'refundMethod') == { 'reason' => 'CUSTOMER', 'restock' => true, 'refundMethod' => { 'originalPaymentMethodsRefund' => true } } })
        .to have_been_requested.once
      note = private_notes.sole
      expect(note.content).to eq('Cancelled order #1001. Reason: customer. Payment refunded. Items restocked.')
      expect(note.sender).to eq(admin)
      expect(result.note_message_id).to eq(note.id)
    end

    it 'returns the recorded outcome for a repeated request, without asking the store again' do
      stub_order
      cancellation = stub_cancel

      first = cancel
      second = cancel

      expect(second.id).to eq(first.id)
      expect(cancellation).to have_been_requested.once
      expect(private_notes.count).to eq(1)
    end

    it 'reports the cancellation as running when the store has not finished, and settles it later' do
      stub_order
      stub_cancel(done: false)
      allow(Process).to receive(:clock_gettime).and_wrap_original do |original, *args|
        @ticks = (@ticks || 0) + 1
        original.call(*args) + (@ticks > 3 ? 60 : 0)
      end

      result = cancel
      expect(result.outcome).to eq('running')
      expect(private_notes).to be_empty
      allow(Process).to receive(:clock_gettime).and_call_original

      WebMock.reset!
      stub_order
      stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: true } })
      stub_shopify(:order_details_limited, data: { order: open_order.merge('cancelledAt' => '2026-11-05T12:00:00Z') })
      runner.settle_open!

      expect(result.reload.outcome).to eq('accepted')
      expect(private_notes.count).to eq(1)
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation order_cancel') }
    end

    it 'takes a job that ends with the order not cancelled as the store\'s refusal' do
      stub_const('Inclamo::Shopify::Actions::Cancel::WAIT', 0)
      stub_order
      stub_cancel(done: true)
      stub_shopify(:order_details_limited, data: { order: open_order })

      result = cancel

      expect(result).to have_attributes(outcome: 'refused', refusal: 'not_cancelled')
      expect(private_notes).to be_empty
    end

    it 'settles a running cancellation from one read of the store, without waiting, when the store did not cancel' do
      record_running = Inclamo::OrderAction.create!(account: account, conversation: conversation, user: admin, action_id: 'action-cancel-0010', action: 'cancel',
                                                    order_id: order_id, order_number: '#1001', outcome: 'running', progress: { 'job_id' => 'gid://shopify/Job/1' })
      stub_order
      stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: true } })
      stub_shopify(:order_details_limited, data: { order: open_order })

      runner.settle_open!

      expect(record_running.reload).to have_attributes(outcome: 'refused', refusal: 'not_cancelled')
      expect(a_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('query job_status') }).to have_been_made.once
    end

    it 'follows the order alone when the store gives no job, and never cancels twice' do
      stub_const('Inclamo::Shopify::Actions::Cancel::WAIT', 0)
      stub_order
      cancellation = stub_shopify(:order_cancel, data: { orderCancel: { job: nil, orderCancelUserErrors: [] } })
      stub_shopify(:order_details_limited, data: { order: open_order })

      first = cancel

      expect(first.outcome).to eq('running')
      expect(a_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('query job_status') }).not_to have_been_made

      stub_shopify(:order_details_limited, data: { order: open_order.merge('cancelledAt' => '2026-11-05T12:00:00Z') })
      expect(cancel.outcome).to eq('accepted')
      expect(cancellation).to have_been_requested.once
    end

    it 'shows the reason of the store when it refuses, and writes no note' do
      stub_order
      stub_cancel(errors: [{ field: ['orderId'], message: 'Cannot cancel an order with an active return', code: 'INVALID' }])

      result = cancel

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_refused', store_message: 'Cannot cancel an order with an active return')
      expect(private_notes).to be_empty
    end

    it 'does not offer to cancel an order that is already cancelled' do
      stub_order(open_order.merge('cancelledAt' => '2026-11-01T10:00:00Z'))
      cancellation = stub_cancel

      expect(cancel.refusal).to eq('already_cancelled')
      expect(cancellation).not_to have_been_requested
    end

    it 'records an attempt whose answer was lost as unknown, neither done nor failed' do
      stub_order
      stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation order_cancel') }.to_timeout

      result = cancel

      expect(result.outcome).to eq('unknown')
      expect(private_notes).to be_empty
    end

    it 'records a cancellation the store could not be reached for as refused: it was never sent' do
      stub_order
      Inclamo::Shopify::OrderReader.new(record).order(order_id) # read before the store becomes unreachable
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |http| allow(http).to receive(:start).and_raise(SocketError) }
      end

      result = cancel

      expect(result).to have_attributes(outcome: 'refused', refusal: 'store_unreachable', store_message: 'unreachable')
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation order_cancel') }
    end

    it 'refuses a reason the store does not know' do
      stub_order

      expect(cancel(params: { 'reason' => 'because' }).refusal).to eq('invalid_reason')
    end
  end

  describe 'changing the shipping address' do
    def change_address(id: 'action-address-0001', node: open_order)
      stub_order(node)
      runner.perform(action: 'address', action_id: id, order_id: order_id, extra: { address: address })
    end

    it 'sends the new address to the store and keeps none of it' do
      update = stub_shopify(:order_address_update, data: { orderUpdate: { order: { id: order_id }, userErrors: [] } })

      result = change_address

      expect(result.outcome).to eq('accepted')
      expect(update.with { |r| JSON.parse(r.body).dig('variables', 'input', 'shippingAddress') == { 'firstName' => 'Maya', 'lastName' => 'Example', 'address1' => '2 Example Avenue', 'city' => 'Springfield', 'provinceCode' => 'IL', 'zip' => '62702', 'countryCode' => 'US' } })
        .to have_been_requested.once
      expect(private_notes.sole.content).to eq('Changed the shipping address of order #1001.')
      expect(Inclamo::OrderAction.all.to_json + private_notes.pluck(:content).join).not_to match(/Example Avenue|62702|Springfield/)
    end

    it 'sends every field the form holds, a cleared one as empty, so that it is cleared at the store too' do
      update = stub_shopify(:order_address_update, data: { orderUpdate: { order: { id: order_id }, userErrors: [] } })
      stub_order

      runner.perform(action: 'address', action_id: 'action-address-0004', order_id: order_id,
                     extra: { address: address.merge('company' => 'Example Works', 'address2' => '  ', 'phone' => '') })

      expect(update.with do |r|
        sent = JSON.parse(r.body).dig('variables', 'input', 'shippingAddress')
        sent.is_a?(Hash) && sent['company'] == 'Example Works' && sent.key?('address2') && sent['address2'].nil? && sent.key?('phone') && sent['phone'].nil?
      end).to have_been_requested.once
    end

    it 'is not available for an order that has shipped' do
      result = change_address(node: shopify_fixture('order_details_shipped')['order'])

      expect(result.refusal).to eq('already_shipped')
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('mutation') }
    end

    it 'is not available when the store hides customer data' do
      record.update!(customer_data_mode: 'limited')

      result = runner.perform(action: 'address', action_id: 'action-address-0002', order_id: order_id, extra: { address: address })

      expect(result.refusal).to eq('customer_data_hidden')
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'shows the reason of the store when it refuses the address' do
      stub_shopify(:order_address_update, data: { orderUpdate: { order: nil, userErrors: [{ field: ['shippingAddress'], message: 'Country/region not supported' }] } })

      expect(change_address).to have_attributes(outcome: 'refused', store_message: 'Country/region not supported')
    end

    it 'asks for the fields an address cannot do without' do
      stub_order

      result = runner.perform(action: 'address', action_id: 'action-address-0003', order_id: order_id, extra: { address: { 'zip' => '1' } })

      expect(result.refusal).to eq('address_incomplete')
    end
  end

  describe 'attempts left open' do
    before { stub_order }

    def open_attempt(outcome:, progress: {}, updated_at: Time.current, id: 'action-cancel-0020')
      Inclamo::OrderAction.create!(account: account, conversation: conversation, user: admin, action_id: id, action: 'cancel', order_id: order_id,
                                   order_number: '#1001', params: { 'reason' => 'customer' }, outcome: outcome, progress: progress, updated_at: updated_at)
    end

    it 'leaves an attempt another request is working on to that request, also when the same confirmation is sent again' do
      in_flight = open_attempt(outcome: 'pending')

      runner.settle_open!
      repeated = cancel(id: in_flight.action_id)

      expect(repeated).to have_attributes(id: in_flight.id, outcome: 'pending')
      expect(in_flight.reload.outcome).to eq('pending')
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('order_cancel') }
      expect(private_notes).to be_empty
    end

    it 'settles an attempt whose answer was lost by reading the order, without cancelling again' do
      lost = open_attempt(outcome: 'unknown')
      stub_shopify(:order_details_limited, data: { order: open_order.merge('cancelledAt' => '2026-11-05T12:00:00Z') })

      runner.settle_open!

      expect(lost.reload.outcome).to eq('accepted')
      expect(private_notes.count).to eq(1)
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('order_cancel') }
    end

    it 'keeps it unknown while the order does not tell' do
      lost = open_attempt(outcome: 'unknown')
      stub_shopify(:order_details_limited, data: { order: open_order })

      runner.settle_open!

      expect(lost.reload.outcome).to eq('unknown')
      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].include?('order_cancel') }
    end

    it 'takes an attempt pending for longer than a request can last as unknown' do
      stale = open_attempt(outcome: 'pending', updated_at: 10.minutes.ago)
      stub_shopify(:order_details_limited, data: { order: open_order })

      runner.settle_open!

      expect(stale.reload.outcome).to eq('unknown')
    end

    it 'writes one note when two reads settle the same attempt' do
      lost = open_attempt(outcome: 'unknown')
      stub_shopify(:order_details_limited, data: { order: open_order.merge('cancelledAt' => '2026-11-05T12:00:00Z') })
      stale_copy = Inclamo::OrderAction.find(lost.id)

      runner.settle_open!
      runner.send(:resolve, stale_copy)

      expect(lost.reload.outcome).to eq('accepted')
      expect(private_notes.count).to eq(1)
    end
  end

  describe 'an action id of another attempt' do
    it 'is refused without showing or settling that attempt, and nothing lands in this conversation' do
      elsewhere = create(:conversation, account: account)
      theirs = Inclamo::OrderAction.create!(account: account, conversation: elsewhere, user: admin, action_id: 'action-cancel-0030', action: 'cancel',
                                            order_id: order_id, order_number: '#1001', outcome: 'unknown')

      result = cancel(id: theirs.action_id)

      expect(result).to have_attributes(outcome: 'refused', refusal: 'action_id_taken', order_number: nil)
      expect(result).not_to be_persisted
      expect(theirs.reload.outcome).to eq('unknown')
      expect(private_notes).to be_empty
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'is refused for another order or another action in the same conversation' do
      mine = Inclamo::OrderAction.create!(account: account, conversation: conversation, user: admin, action_id: 'action-cancel-0031', action: 'cancel',
                                          order_id: order_id, outcome: 'unknown')

      expect(runner.perform(action: 'refund', action_id: mine.action_id, order_id: order_id).refusal).to eq('action_id_taken')
      expect(runner.perform(action: 'cancel', action_id: mine.action_id, order_id: 'gid://shopify/Order/2').refusal).to eq('action_id_taken')
    end
  end

  it 'forgets the cached orders of the account after an action' do
    stub_order
    stub_cancel

    expect { cancel }.to(change { Redis::Alfred.get(Inclamo::Shopify::OrderReader.generation_key(account.id)).to_i })
  end

  it 'keeps the action records when the store connection is removed' do
    stub_order
    stub_cancel
    cancel

    record.destroy!

    expect(Inclamo::OrderAction.where(account: account).pluck(:outcome)).to eq(['accepted'])
    expect(private_notes.count).to eq(1)
  end
end
