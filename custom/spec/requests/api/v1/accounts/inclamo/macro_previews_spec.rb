# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo macro previews API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:order) { shopify_fixture('order_details_open')['order'] }
  let(:currency) { order['currencyCode'] }
  let(:total) { order.dig('totalPriceSet', 'shopMoney', 'amount') }
  let(:lines) { order.dig('lineItems', 'nodes') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, custom_attributes: { 'shopify_order_id' => order['id'], 'shopify_order_number' => '#1001' }) }
  let(:url) { "/api/v1/accounts/#{account.id}/inclamo/macro_previews" }
  let(:connection) { create(:inclamo_shopify_connection, account: account) }

  before do
    connection
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify(:order_details, data: { order: order })
  end

  def macro_with(*names, visibility: :global, by: admin)
    create(:macro, account: account, created_by: by, visibility: visibility,
                   actions: names.map { |name| { 'action_name' => name, 'action_params' => name == 'send_message' ? ['Sorry'] : [] } })
  end

  def preview(macro, user = admin, conversation_id: conversation.display_id)
    post url, params: { macro_id: macro.id, conversation_id: conversation_id }, headers: user.create_new_auth_token, as: :json
  end

  def stub_suggestion(amount: total, shipping: '0.0')
    stub_refund_suggestion(order, amount: amount, shipping: shipping)
  end

  it 'names the tied order and what each order step will do, with the amount the step then refunds' do
    stub_suggestion
    stub_shopify(:refund_create, data: { refundCreate: { refund: { id: 'gid://shopify/Refund/1', totalRefundedSet: { shopMoney: { amount: total, currencyCode: currency } } }, userErrors: [] } })
    macro = macro_with('inclamo_refund_full', 'send_message', 'resolve_conversation')

    preview(macro)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('order' => { 'id' => order['id'], 'number' => '#1001' }, 'digest' => Inclamo::Shopify::MacroSteps.digest(macro),
                                       'steps' => [{ 'position' => 0, 'step' => 'inclamo_refund_full', 'amount' => total.to_d.to_s('F'), 'currency' => currency }])
    expect(Inclamo::OrderAction.count).to eq(0)

    Macros::ExecutionService.new(macro, conversation, admin).perform
    refunded = a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^mutation refund_create\b/) &&
        body.dig('variables', 'input', 'transactions').sum { |transaction| transaction['amount'].to_d }.to_s('F') == response.parsed_body['steps'][0]['amount']
    end
    expect(refunded).to have_been_made.once
  end

  it 'gives the shipping amount for a shipping refund, the refund for a cancellation and the units of a replacement' do
    stub_refund_suggestion(order, amount: '50.0', shipping: '50.0') { |variables| variables['refundShipping'] == true }
    stub_refund_suggestion(order, amount: total, shipping: '50.0') { |variables| variables['suggestFullRefund'] == true }

    preview(macro_with('inclamo_refund_shipping', 'inclamo_cancel_order', 'inclamo_replacement'))

    steps = response.parsed_body['steps']
    expect(steps[0]).to include('step' => 'inclamo_refund_shipping', 'amount' => '50.0', 'currency' => currency)
    expect(steps[1]).to include('step' => 'inclamo_cancel_order', 'amount' => (total.to_d - 50).to_s('F'), 'currency' => currency)
    expect(steps[2]).to include('step' => 'inclamo_replacement', 'units' => lines.sum { |line| line['quantity'] })
  end

  it 'shows each order step as it will be after the steps before it, and none after a step that stops the macro' do
    stub_refund_suggestion(order, amount: '40.0', shipping: '40.0') { |variables| variables['refundShipping'] == true }
    stub_refund_suggestion(order, amount: total, shipping: '40.0') { |variables| variables['suggestFullRefund'] == true }

    preview(macro_with('inclamo_refund_shipping', 'inclamo_cancel_order', 'inclamo_refund_full', 'send_message', 'inclamo_replacement'))

    steps = response.parsed_body['steps']
    expect(steps[0]).to include('step' => 'inclamo_refund_shipping', 'amount' => '40.0')
    expect(steps[1]).to include('step' => 'inclamo_cancel_order', 'amount' => (total.to_d - 40).to_s('F'))
    expect(steps[2]).to include('step' => 'inclamo_refund_full', 'refusal' => 'nothing_to_refund')
    expect(steps[3]).to eq('position' => 4, 'step' => 'inclamo_replacement', 'after_stop' => true)
  end

  it 'gives a cancellation after a full refund nothing more to refund' do
    stub_suggestion

    preview(macro_with('inclamo_refund_full', 'inclamo_cancel_order'))

    steps = response.parsed_body['steps']
    expect(steps[0]).to include('amount' => total.to_d.to_s('F'))
    expect(steps[1]).to eq('position' => 1, 'step' => 'inclamo_cancel_order', 'refund' => 'none_left')
  end

  it 'does not refuse a cancellation when only the amount it refunds cannot be worked out' do
    stub_shopify(:refund_suggestion, errors: [{ message: 'Internal error' }])

    preview(macro_with('inclamo_cancel_order'))

    expect(response.parsed_body['steps']).to eq([{ 'position' => 0, 'step' => 'inclamo_cancel_order', 'refund' => 'unknown' }])
  end

  it 'tells a cancellation of an order refunded already from one never paid' do
    stub_shopify(:order_details, data: { order: order.merge('totalRefundedSet' => order['totalReceivedSet'], 'refundable' => false) })
    preview(macro_with('inclamo_cancel_order'))
    expect(response.parsed_body['steps'][0]).to include('refund' => 'none_left')

    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify(:order_details, data: { order: order.merge('totalReceivedSet' => { 'shopMoney' => { 'amount' => '0.0', 'currencyCode' => currency } }) })
    preview(macro_with('inclamo_cancel_order'))
    expect(response.parsed_body['steps'][0]).to include('refund' => 'unpaid')
  end

  it 'counts for a replacement only the units the order still holds' do
    order['lineItems']['nodes'][1]['currentQuantity'] = 0
    stub_shopify(:order_details, data: { order: order })

    preview(macro_with('inclamo_replacement'))

    expect(response.parsed_body['steps'][0]).to include('units' => lines.size - 1)
  end

  it 'answers that no order is tied without calling the store' do
    conversation.update!(custom_attributes: {})

    macro = macro_with('send_message', 'inclamo_refund_full')

    preview(macro)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('order' => nil, 'steps' => [{ 'position' => 1, 'step' => 'inclamo_refund_full' }], 'digest' => Inclamo::Shopify::MacroSteps.digest(macro))
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'says beforehand why a step will be refused, without calling the store for an agent without the role' do
    preview(macro_with('inclamo_refund_full'), agent)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['steps']).to eq([{ 'position' => 0, 'step' => 'inclamo_refund_full', 'refusal' => 'not_allowed', 'message' => nil }])
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'names the missing scopes' do
    connection.update!(scopes: %w[read_customers read_orders write_orders])

    preview(macro_with('inclamo_replacement'))

    expect(response.parsed_body['steps'][0]).to include('refusal' => 'missing_scope', 'missing_scopes' => %w[write_draft_orders read_products])
  end

  it 'requires refund permission as well as cancellation permission in a macro preview' do
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['cancel'])
    preview(macro_with('inclamo_cancel_order'), agent)

    expect(response.parsed_body['steps'].first).to include('refusal' => 'not_allowed')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'reports an order with nothing left to refund' do
    stub_shopify(:order_details, data: { order: order.merge('totalRefundedSet' => order['totalReceivedSet'], 'refundable' => false) })

    preview(macro_with('inclamo_refund_full'))

    expect(response.parsed_body['steps'][0]).to include('refusal' => 'nothing_to_refund')
  end

  it 'lists nothing for a macro without order steps' do
    macro = macro_with('send_message')

    preview(macro)

    expect(response.parsed_body).to eq('order' => { 'id' => order['id'], 'number' => '#1001' }, 'steps' => [], 'digest' => Inclamo::Shopify::MacroSteps.digest(macro))
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'is not found for a macro of another account' do
    other = create(:macro, account: create(:account))

    preview(other)

    expect(response).to have_http_status(:not_found)
  end

  it 'is refused for a personal macro of somebody else' do
    preview(macro_with('inclamo_refund_full', visibility: :personal), agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'is refused in a conversation the agent may not see' do
    hidden = create(:conversation, account: account, inbox: create(:inbox, account: account))

    preview(macro_with('inclamo_refund_full'), agent, conversation_id: hidden.display_id)

    expect(response).to have_http_status(:unauthorized)
  end
end
