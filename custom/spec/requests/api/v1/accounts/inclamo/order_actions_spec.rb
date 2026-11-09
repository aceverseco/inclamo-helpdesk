# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo order actions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}" }
  let(:open_order) { shopify_fixture('order_details_open')['order'] }
  let(:request_body) { { action_name: 'cancel', action_id: 'action-cancel-0001', order_id: open_order['id'], params: { reason: 'customer', refund: true, restock: true } } }

  before do
    create(:inclamo_shopify_connection, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_const('Inclamo::Shopify::Actions::Cancel::POLL', 0)
    stub_shopify(:order_details, data: { order: open_order })
    stub_shopify(:order_cancel, data: { orderCancel: { job: { id: 'gid://shopify/Job/1', done: true }, orderCancelUserErrors: [] } })
    stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: true } })
    stub_shopify(:order_details_limited, data: { order: open_order.merge('cancelledAt' => '2026-11-05T12:00:00Z') })
  end

  it 'previews cancellation refund amounts with current compound permissions' do
    stub_refund_suggestion(open_order, amount: '125.00')
    post "#{base}/actions/cancel_preview", params: { order_id: open_order['id'], params: { refund: true } }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('amount' => '125.0', 'currency' => open_order['currencyCode'])
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['cancel'])
    post "#{base}/actions/cancel_preview", params: { order_id: open_order['id'], params: { refund: true } }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['refusal']).to eq('not_allowed')
    expect(Inclamo::OrderAction.count).to eq(0)
  end

  it 'performs the action for an administrator and returns its record' do
    post "#{base}/actions", params: request_body, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('outcome' => 'accepted', 'order_number' => '#1001', 'action' => 'cancel')
  end

  it 'is forbidden for an agent without the role, and the store is not called' do
    post "#{base}/actions", params: request_body, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include('outcome' => 'refused', 'refusal' => 'not_allowed')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'cannot refund through cancellation when only cancellation is granted' do
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['cancel'])
    post "#{base}/actions", params: request_body, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'can cancel without refund using only cancellation permission' do
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['cancel'])
    post "#{base}/actions", params: request_body.merge(params: { reason: 'customer', refund: false, restock: true }), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['outcome']).to eq('accepted')
  end

  it 'refuses a discounted new-order preview without discount authority' do
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: ['new_order'])
    post "#{base}/actions/new_order_preview", params: { params: { discount: { type: 'percentage', value: '10' } } }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'checks revocation again when an unsettled request is retried' do
    role = Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), permissions: %w[cancel refund])
    Inclamo::OrderAction.create!(account: account, conversation: conversation, user: agent, action_id: request_body[:action_id],
                                action: 'cancel', order_id: open_order['id'], outcome: 'unknown', params: request_body[:params])
    role.update!(permissions: ['cancel'])
    post "#{base}/actions", params: request_body, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['outcome']).to eq('unknown')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'returns the same record for the same action id' do
    2.times { post "#{base}/actions", params: request_body, headers: admin.create_new_auth_token, as: :json }

    expect(Inclamo::OrderAction.count).to eq(1)
    get "#{base}/actions/action-cancel-0001", headers: admin.create_new_auth_token
    expect(response.parsed_body['outcome']).to eq('accepted')
  end

  it 'lists the attempts made from the conversation, refused ones included' do
    post "#{base}/actions", params: request_body, headers: admin.create_new_auth_token, as: :json
    post "#{base}/actions", params: request_body.merge(action_id: 'action-cancel-0002'), headers: agent.create_new_auth_token, as: :json

    get "#{base}/actions", headers: admin.create_new_auth_token

    expect(response.parsed_body['actions'].pluck('action_id', 'outcome')).to eq([%w[action-cancel-0002 refused], %w[action-cancel-0001 accepted]])
  end

  it 'refuses an action it does not know' do
    post "#{base}/actions", params: request_body.merge(action_name: 'delete_everything'), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'is closed to an agent who cannot see the conversation' do
    outsider = create(:user, account: account, role: :agent)

    post "#{base}/actions", params: request_body, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Inclamo::OrderAction.count).to eq(0)
  end

  it 'shows a cancellation the store is still working on in the panel' do
    Inclamo::OrderAction.create!(account: account, conversation: conversation, user: admin, action_id: 'action-cancel-0009',
                                 action: 'cancel', order_id: open_order['id'], order_number: '#1001', outcome: 'running',
                                 progress: { 'job_id' => 'gid://shopify/Job/1' })
    stub_shopify(:job_status, data: { job: { id: 'gid://shopify/Job/1', done: false } })
    conversation.contact.update!(email: nil, phone_number: nil)

    get "#{base}/panel", headers: admin.create_new_auth_token

    expect(response.parsed_body['open_actions']).to contain_exactly(include('action' => 'cancel', 'outcome' => 'running', 'order_number' => '#1001'))
  end
end
