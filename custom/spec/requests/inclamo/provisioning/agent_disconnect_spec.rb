# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# DELETE stores/{shop}/agent (design D7, task 3.8): the same disconnection as
# the "AI agent" page's button.
RSpec.describe 'App agent connection: disconnecting', type: :request do
  include_context 'with the store app and the AI service'

  def answer
    response.parsed_body
  end

  let(:account) { provisioned.account }
  let(:storefront) { provisioned.storefront_inbox }
  let(:record) { connection_of(account) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }

  before do
    provision
    stub_ai_registration
    connect_agent
    expect(response).to have_http_status(:created)
  end

  # What the agent reads of a conversation, with the bot's token.
  def bot_api(token, conversation)
    get "/api/v1/accounts/#{account.id}/inclamo/ai/conversations/#{conversation.display_id}/messages", headers: { 'api_access_token' => token }, as: :json
    response
  end

  it 'hands the pending conversations to the team, refuses the token at once, and keeps Phone and the labels' do
    removal = stub_ai_removal
    pending = create_list(:conversation, 2, account: account, inbox: storefront.reload)
    expect(pending.map { |conversation| conversation.reload.status }).to eq(%w[pending pending])
    token = bot.access_token.token
    phone_id = record.phone_inbox_id
    expect(bot_api(token, pending.first)).to have_http_status(:ok)

    disconnect_agent

    expect(response).to have_http_status(:ok)
    expect(answer).to eq('contract' => 1, 'state' => 'disconnected', 'ai_service_told' => true)
    expect(pending.map { |conversation| conversation.reload.status }).to eq(%w[open open])
    expect(bot_api(token, pending.first)).to have_http_status(:unauthorized)
    expect(Inbox.exists?(phone_id)).to be(true)
    expect(account.labels.pluck(:title)).to include('inclamo_handover', 'inclamo_call')
    expect(removal.with(headers: { 'Authorization' => "Bearer #{token}" })).to have_been_requested.once
    expect(record.reload).to have_attributes(state: 'disconnected', removal_error: nil)
  end

  it 'disconnects all the same when the AI service does not answer, and says it could not be told' do
    stub_request(:delete, "#{AiServiceStubs::AI_SERVICE_URL}/connections/conn-1").to_timeout

    disconnect_agent

    expect(response).to have_http_status(:ok)
    expect(answer).to eq('contract' => 1, 'state' => 'disconnected', 'ai_service_told' => false)
    expect(record.reload).to have_attributes(state: 'disconnected', removal_error: 'not_answered')
    expect(agent_bots_of(account)).to be_empty
  end

  it 'answers a second call as done, and changes nothing' do
    removal = stub_ai_removal
    disconnect_agent
    disconnected_at = record.reload.disconnected_at

    disconnect_agent

    expect(response).to have_http_status(:ok)
    expect(answer).to eq('contract' => 1, 'state' => 'disconnected', 'ai_service_told' => true)
    expect(record.reload.disconnected_at).to eq(disconnected_at)
    expect(removal).to have_been_requested.once
  end

  it 'disconnects a connection made on the page as well' do
    stub_ai_removal
    disconnect_agent
    administrator = User.from_email('alex@example.test')
    post "/api/v1/accounts/#{account.id}/inclamo/ai/connection",
         params: { connection_code: ai_code, inbox_ids: [storefront.id] }, headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)

    disconnect_agent

    expect(answer).to include('state' => 'disconnected')
    expect(connection_of(account)).to have_attributes(state: 'disconnected', connected_via: 'page')
  end

  it 'answers busy while another connection or disconnection is under way' do
    hold_connection_lock(account)

    disconnect_agent

    expect(response).to have_http_status(:conflict)
    expect(answer).to eq('error' => 'busy')
    expect(response.headers['Retry-After']).to eq('5')
    expect(record.reload).to be_active
  ensure
    release_connection_lock(account)
  end

  it 'answers an account that never had a connection as never connected' do
    provision('second-store.myshopify.com')

    disconnect_agent('second-store.myshopify.com')

    expect(response).to have_http_status(:ok)
    expect(answer).to eq('contract' => 1, 'state' => 'never_connected', 'ai_service_told' => true)
  end
end
