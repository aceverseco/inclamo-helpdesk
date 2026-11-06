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

  it 'names the tied order and what each order step will do, with the amount the step then refunds' do
    stub_suggestion
    stub_shopify(:refund_create, data: { refundCreate: { refund: { id: 'gid://shopify/Refund/1', totalRefundedSet: { shopMoney: { amount: total, currencyCode: currency } } }, userErrors: [] } })
    macro = macro_with('inclamo_refund_full', 'send_message', 'resolve_conversation')

    preview(macro)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('order' => { 'id' => order['id'], 'number' => '#1001' },
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
    stub_suggestion(amount: '50.0', shipping: '50.0')

    preview(macro_with('inclamo_refund_shipping', 'inclamo_cancel_order', 'inclamo_replacement'))

    steps = response.parsed_body['steps']
    expect(steps[0]).to include('step' => 'inclamo_refund_shipping', 'amount' => '50.0', 'currency' => currency)
    expect(steps[1]).to include('step' => 'inclamo_cancel_order', 'currency' => currency)
    expect(steps[2]).to include('step' => 'inclamo_replacement', 'units' => lines.sum { |line| line['quantity'] })
  end

  it 'answers that no order is tied without calling the store' do
    conversation.update!(custom_attributes: {})

    preview(macro_with('send_message', 'inclamo_refund_full'))

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('order' => nil, 'steps' => [{ 'position' => 1, 'step' => 'inclamo_refund_full' }])
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

  it 'reports an order with nothing left to refund' do
    stub_shopify(:order_details, data: { order: order.merge('totalRefundedSet' => order['totalReceivedSet'], 'refundable' => false) })

    preview(macro_with('inclamo_refund_full'))

    expect(response.parsed_body['steps'][0]).to include('refusal' => 'nothing_to_refund')
  end

  it 'lists nothing for a macro without order steps' do
    preview(macro_with('send_message'))

    expect(response.parsed_body).to eq('order' => { 'id' => order['id'], 'number' => '#1001' }, 'steps' => [])
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
