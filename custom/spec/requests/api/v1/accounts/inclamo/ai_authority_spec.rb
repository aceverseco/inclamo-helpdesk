# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'AI order authority', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account, email: customer.dig('defaultEmailAddress', 'emailAddress')) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }
  let(:customer) { shopify_fixture('customer_orders')['customer'] }
  let(:order) { node = shopify_fixture('order_details_open')['order']; node.merge('currentTotalPriceSet' => node['totalPriceSet']) }
  let(:bot_headers) { { 'api_access_token' => bot.access_token.token } }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo" }
  let(:bot_path) { "#{base}/ai/conversations/#{conversation.display_id}" }
  let(:staff_path) { "#{base}/conversations/#{conversation.display_id}/ai_proposals" }
  let(:input) { { request_id: 'ai-address-request-001', action_name: 'address', order_id: order['id'], address: { address1: '17 Test Lane', city: 'Kyiv', country_code: 'UA' } } }
  let!(:connection) { create(:inclamo_ai_connection, account: account, agent_bot: bot, inbox_ids: [inbox.id]) }

  before do
    create(:inclamo_shopify_connection, account: account, shop_currency: 'UAH')
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: agent)
    stub_shopify_fixture(:customers_search, 'customers_search_one')
    stub_shopify(:customer_orders, data: { customer: customer })
    stub_shopify(:order_details, data: { order: order })
    stub_shopify(:order_address_update, data: { orderUpdate: { order: { id: order['id'] }, userErrors: [] } })
  end

  def propose(values = input)
    post "#{bot_path}/proposals", params: values, headers: bot_headers, as: :json
    expect(response).to have_http_status(:created), response.body
    response.parsed_body
  end

  def approve(proposal, user = admin, digest: proposal['review_digest'])
    post "#{staff_path}/#{proposal['id']}/approve", params: { review_digest: digest }, headers: user.create_new_auth_token, as: :json
  end

  def allow_autonomy(maximum: '10000', states: ['UNFULFILLED'])
    Inclamo::AiPolicy.create!(account: account, action: 'address', mode: 'autonomous', limits: { currency: 'UAH', max_amount: maximum, allowed_states: states })
    conversation.contact.update!(identifier: customer['id'])
    conversation.contact_inbox.update!(hmac_verified: true)
    conversation.update!(status: :pending, assignee_id: nil)
  end

  def execute(proposal)
    post "#{bot_path}/proposals/#{proposal['id']}/execute", headers: bot_headers, as: :json
  end

  def mutation
    a_request(:post, shopify_graphql_url).with { |request| JSON.parse(request.body)['query'].match?(/^mutation order_address_update\b/) }
  end

  it 'defaults every operation to proposal and lets only administrators save valid limits' do
    get "#{base}/ai_policies", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['policies'].map { |row| row['mode'] }.uniq).to eq(['propose'])
    patch "#{base}/ai_policies/refund", params: { mode: 'autonomous', limits: {} }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Inclamo::AiPolicy.count).to eq(0)
    patch "#{base}/ai_policies/refund", params: { mode: 'forbidden' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'validates currency, states and discount percentages without changing the saved policy' do
    policy = Inclamo::AiPolicy.create!(account: account, action: 'discount', mode: 'forbidden')
    [['USD', '10'], ['UAH', '101']].each do |currency, percentage|
      patch "#{base}/ai_policies/discount", params: { mode: 'autonomous', limits: { currency: currency, max_amount: '50', max_percentage: percentage } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(policy.reload.mode).to eq('forbidden')
    patch "#{base}/ai_policies/address", params: { mode: 'autonomous', limits: { currency: 'UAH', max_amount: '50', allowed_states: ['made_up'] } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'creates an encrypted immutable proposal without changing Shopify' do
    proposal = propose
    expect(proposal).to include('state' => 'proposed', 'can_approve' => false)
    expect(proposal.dig('request', 'address', 'address1')).to eq('17 Test Lane')
    raw = Inclamo::AiProposal.connection.select_value('SELECT payload FROM inclamo_ai_proposals ORDER BY id DESC LIMIT 1')
    expect(raw).not_to include('17 Test Lane')
    expect(mutation).not_to have_been_made
    execute(proposal)
    expect(response.parsed_body['error']).to eq('approval_required')
    expect(mutation).not_to have_been_made
  end

  it 'deduplicates proposals and rejects identifier reuse with changed parameters' do
    first = propose
    expect(propose['id']).to eq(first['id'])
    post "#{bot_path}/proposals", params: input.merge(address: { address1: 'Changed', city: 'Kyiv', country_code: 'UA' }), headers: bot_headers, as: :json
    expect(response.parsed_body['error']).to eq('request_id_taken')
    expect(Inclamo::AiProposal.count).to eq(1)
  end

  it 'rejects another customer target and foreign inboxes before a mutation' do
    stub_shopify(:order_details, data: { order: order.merge('customer' => { 'id' => 'gid://shopify/Customer/999' }) })
    post "#{bot_path}/proposals", params: input, headers: bot_headers, as: :json
    expect(response.parsed_body['error']).to eq('not_customers_target')
    connection.update!(inbox_ids: [])
    post "#{bot_path}/proposals", params: input, headers: bot_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(mutation).not_to have_been_made
  end

  it 'rejects unprivileged staff and honors permission revocation after review' do
    proposal = propose
    approve(proposal, agent)
    expect(response).to have_http_status(:forbidden)
    grant = Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['address'])
    get staff_path, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['proposals'].first['can_approve']).to be(true)
    grant.destroy!
    approve(proposal, agent)
    expect(response).to have_http_status(:forbidden)
    expect(mutation).not_to have_been_made
  end

  it 'approves the exact proposal once and records bot and human in the audit' do
    proposal = propose
    2.times { approve(proposal) }
    expect(response.parsed_body['state']).to eq('accepted')
    expect(response.parsed_body.dig('approver', 'id')).to eq(admin.id)
    expect(mutation).to have_been_made.once
    action = Inclamo::OrderAction.last
    expect(action.ai_proposal_id).to eq(proposal['id'])
    expect(Message.find(action.note_message_id).content).to include(bot.name, admin.name)
  end

  it 'requires refreshed review after the order changes and rejects old digests' do
    proposal = propose
    stub_shopify(:order_details, data: { order: order.merge('note' => 'Changed by merchant') })
    approve(proposal)
    expect(response.parsed_body['error']).to eq('review_changed')
    post "#{staff_path}/#{proposal['id']}/refresh", headers: admin.create_new_auth_token, as: :json
    refreshed = response.parsed_body
    expect(refreshed['review_digest']).not_to eq(proposal['review_digest'])
    approve(refreshed, digest: proposal['review_digest'])
    expect(response.parsed_body['error']).to eq('review_changed')
    approve(refreshed)
    expect(response.parsed_body['state']).to eq('accepted')
  end

  it 'does not execute rejected or expired proposals' do
    proposal = propose
    post "#{staff_path}/#{proposal['id']}/reject", headers: admin.create_new_auth_token, as: :json
    approve(proposal)
    expect(response.parsed_body['error']).to eq('already_decided')
    second = propose(input.merge(request_id: 'ai-address-request-002'))
    Inclamo::AiProposal.find(second['id']).update!(expires_at: 1.minute.ago)
    approve(second)
    expect(response.parsed_body['error']).to eq('expired')
    expect(mutation).not_to have_been_made
  end

  it 'applies current policy to a previously displayed proposal' do
    proposal = propose
    Inclamo::AiPolicy.create!(account: account, action: 'address', mode: 'forbidden')
    approve(proposal)
    expect(response.parsed_body['error']).to eq('policy_forbidden')
    expect(mutation).not_to have_been_made
  end

  it 'executes an explicitly bounded autonomous operation exactly once' do
    allow_autonomy
    proposal = propose
    2.times { execute(proposal) }
    expect(response.parsed_body['state']).to eq('accepted')
    expect(response.parsed_body['approver']).to be_nil
    expect(mutation).to have_been_made.once
    expect(Inclamo::OrderAction.last.user).to be_nil
  end

  it 'requires verified identity instead of trusting a widget email' do
    allow_autonomy
    conversation.contact_inbox.update!(hmac_verified: false)
    proposal = propose
    execute(proposal)
    expect(response.parsed_body['error']).to eq('identity_unverified')
    expect(mutation).not_to have_been_made
    post "#{staff_path}/#{proposal['id']}/verify_identity", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    execute(proposal)
    expect(response.parsed_body['state']).to eq('accepted')
  end

  it 'accepts a signed email only when it belongs to the matched Shopify customer' do
    allow_autonomy
    contact.update!(identifier: customer.dig('defaultEmailAddress', 'emailAddress'))
    proposal = propose
    execute(proposal)
    expect(response.parsed_body['state']).to eq('accepted')
    expect(mutation).to have_been_made.once
  end

  it 'does not authorize a phone-matched customer through somebody else signed email' do
    allow_autonomy
    contact.update!(email: 'unrelated.example@example.com', identifier: 'unrelated.example@example.com',
                    phone_number: customer.dig('defaultPhoneNumber', 'phoneNumber'))
    get "#{bot_path}/orders", headers: bot_headers, as: :json
    expect(response.parsed_body.dig('customer', 'id')).to eq(customer['id'])
    expect(response.parsed_body['identity_verified']).to be(false)
    proposal = propose
    execute(proposal)
    expect(response.parsed_body['error']).to eq('identity_unverified')
    expect(mutation).not_to have_been_made
  end

  it 'refuses autonomous operations above limits and outside allowed states' do
    policy = allow_autonomy(maximum: '1')
    proposal = propose
    execute(proposal)
    expect(response.parsed_body['error']).to eq('amount_limit')
    Inclamo::AiPolicy.last.update!(limits: { currency: 'UAH', max_amount: '10000', allowed_states: ['FULFILLED'] })
    execute(proposal)
    expect(response.parsed_body['error']).to eq('state_limit')
    expect(mutation).not_to have_been_made
  end

  it 'refuses autonomy after takeover, service failure and disconnect' do
    allow_autonomy
    proposal = propose
    conversation.update!(status: :open)
    execute(proposal)
    expect(response.parsed_body['error']).to eq('human_takeover')
    conversation.update!(status: :pending, assignee_id: nil)
    connection.update!(state: 'failing')
    execute(proposal)
    expect(response.parsed_body['error']).to eq('ai_unavailable')
    connection.update!(state: 'disconnected')
    execute(proposal)
    expect(response).to have_http_status(:unauthorized)
    expect(mutation).not_to have_been_made
  end

  it 'never retries a write after a lost Shopify response' do
    proposal = propose
    stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].match?(/^mutation order_address_update\b/) }.to_timeout
    2.times { approve(proposal) }
    expect(response.parsed_body['state']).to eq('unknown')
    expect(mutation).to have_been_made.once
  end
  it 'does not let widget attributes redirect a new order to another customer' do
    contact.update!(custom_attributes: { Inclamo::Shopify::CustomerMatcher::REMEMBERED => 'gid://shopify/Customer/999' })
    stub_shopify_fixture(:new_order_calculate, 'new_order_calculate')
    stub_shopify_fixture(:new_order_create, 'new_order_create')
    proposal = propose(request_id: 'new-customer-scope-001', action_name: 'new_order',
                       params: { lines: [{ variant_id: 'gid://shopify/ProductVariant/1', quantity: 1 }], delivery: 'reply' })
    approve(proposal)
    expect(response.parsed_body['state']).to eq('accepted')
    expect(a_request(:post, shopify_graphql_url).with do |request|
      sent = JSON.parse(request.body)
      sent['query'].match?(/^mutation new_order_create\b/) && sent.dig('variables', 'input', 'purchasingEntity', 'customerId') == customer['id']
    end).to have_been_made.once
  end

  it 'requires refund policy and staff rights for a cancellation that returns money' do
    stub_refund_suggestion(order, amount: order.dig('totalPriceSet', 'shopMoney', 'amount'))
    proposal = propose(request_id: 'compound-cancel-001', action_name: 'cancel', order_id: order['id'], params: { reason: 'CUSTOMER', refund: true })
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['cancel'])
    approve(proposal, agent)
    expect(response).to have_http_status(:forbidden)
    Inclamo::AiPolicy.create!(account: account, action: 'refund', mode: 'forbidden')
    approve(proposal)
    expect(response.parsed_body['error']).to eq('policy_forbidden')
    expect(a_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].match?(/^mutation order_cancel\b/) }).not_to have_been_made
  end

  it 'requires the discount policy for a discounted new order' do
    Inclamo::AiPolicy.create!(account: account, action: 'discount', mode: 'forbidden')
    post "#{bot_path}/proposals", params: { request_id: 'discount-compound-001', action_name: 'new_order',
                                           params: { lines: [], discount: { type: 'percentage', value: '10' }, delivery: 'reply' } }, headers: bot_headers, as: :json
    expect(response.parsed_body['error']).to eq('policy_forbidden')
  end

  it 'shows the selected refund products, payment destination and actual restocking outcome' do
    stub_refund_suggestion(order, amount: '25.0')
    line = order.dig('lineItems', 'nodes').first
    proposal = propose(request_id: 'refund-summary-001', action_name: 'refund', order_id: order['id'],
                       params: { mode: 'items', items: [{ line_item_id: line['id'], quantity: 1 }], restock: false, notify: false })
    effect = proposal.dig('summary', 'effect')
    expect(effect['items']).to contain_exactly(include('title' => line['title'], 'quantity' => 1))
    expect(effect).to include('amount' => '25.0', 'restocked_items' => 0)
    expect(effect['destinations']).to contain_exactly(include('gateway' => 'Manual', 'amount' => '25.0'))
    expect(Inclamo::OrderAction.count).to eq(0)
  end

  it 'does not accept unrelated changes or a bot-provided expected total' do
    post "#{bot_path}/proposals", params: input.merge(params: { refund: true }), headers: bot_headers, as: :json
    expect(response.parsed_body['error']).to eq('invalid_request')
    post "#{bot_path}/proposals", params: { request_id: 'untrusted-summary-001', action_name: 'edit_items', order_id: order['id'],
                                           params: { expected: { total_after: '0', balance: '0' } } }, headers: bot_headers, as: :json
    expect(response.parsed_body['error']).to eq('invalid_request')
  end

end
