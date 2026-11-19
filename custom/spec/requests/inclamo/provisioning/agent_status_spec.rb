# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# GET stores/{shop}/agent (design D7, task 3.7): how the connection is doing.
RSpec.describe 'App agent connection: the status call', type: :request do
  include_context 'with the store app and the AI service'

  def answer
    response.parsed_body
  end

  let(:account) { provisioned.account }
  let(:storefront) { provisioned.storefront_inbox }
  let(:keys) do
    %w[connected_at connected_via contract inbox_ids last_delivered_at last_error last_failed_at last_reply_at phone_inbox_id state]
  end

  before { provision }

  def connect_through_app
    stub_ai_registration
    connect_agent
    expect(response).to have_http_status(:created)
    connection_of(account)
  end

  it 'answers an account that never had a connection with every field empty' do
    ask_agent_status

    expect(response).to have_http_status(:ok)
    expect(answer).to eq(
      'contract' => 1, 'state' => 'never_connected', 'connected_via' => nil, 'inbox_ids' => [], 'phone_inbox_id' => nil,
      'connected_at' => nil, 'last_reply_at' => nil, 'last_delivered_at' => nil, 'last_failed_at' => nil, 'last_error' => nil
    )
  end

  it 'answers a connected account with its inboxes and its delivery times, and nothing secret' do
    record = connect_through_app
    delivered = Time.zone.parse('2026-11-17T11:40:10Z')
    Inclamo::AiConnection.record_delivery(record.id, at: delivered)
    Inclamo::AiConnection.record_reply(record.id, at: delivered + 2.seconds)

    ask_agent_status

    expect(answer).to eq(
      'contract' => 1, 'state' => 'connected', 'connected_via' => 'app', 'inbox_ids' => [storefront.id],
      'phone_inbox_id' => record.phone_inbox_id, 'connected_at' => record.connected_at.utc.iso8601,
      'last_reply_at' => '2026-11-17T11:40:12Z', 'last_delivered_at' => '2026-11-17T11:40:10Z', 'last_failed_at' => nil, 'last_error' => nil
    )
    bot = AgentBot.find(record.agent_bot_id)
    [bot.access_token.token, bot.secret, AgentProvisioningRequests::PAIRING_TOKEN, record.connection_id].each do |secret|
      expect(response.body).not_to include(secret)
    end
  end

  it 'answers a failing connection with the time and kind of the failure' do
    record = connect_through_app
    failed = Time.zone.parse('2026-11-17T12:00:00Z')
    Inclamo::AiConnection.record_failure(record.id, 'http_503', at: failed)

    ask_agent_status

    expect(answer).to include('state' => 'failing', 'last_failed_at' => '2026-11-17T12:00:00Z', 'last_error' => 'http_503',
                              'inbox_ids' => [storefront.id])
  end

  it 'answers a disconnected account as disconnected, answering in no inbox' do
    record = connect_through_app
    stub_ai_removal
    disconnect_agent

    ask_agent_status

    expect(answer).to include('state' => 'disconnected', 'connected_via' => 'app', 'inbox_ids' => [], 'phone_inbox_id' => record.phone_inbox_id)
  end

  it 'follows a connection made again on the page with other inboxes' do
    connect_through_app
    administrator = User.from_email('alex@example.test')
    email = create(:inbox, :with_email, account: account)
    stub_ai_removal
    delete "/api/v1/accounts/#{account.id}/inclamo/ai/connection", headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    ask_agent_status
    expect(answer['state']).to eq('disconnected')

    post "/api/v1/accounts/#{account.id}/inclamo/ai/connection",
         params: { connection_code: ai_code, inbox_ids: [email.id] }, headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)

    ask_agent_status

    expect(answer).to include('state' => 'connected', 'connected_via' => 'page', 'inbox_ids' => [email.id])
  end

  it 'answers no field of a conversation, whatever the conversations hold' do
    connect_through_app
    conversation = create(:conversation, account: account, inbox: storefront.reload)
    create(:message, conversation: conversation, account: account, inbox: storefront, content: 'A shopper wrote this')

    ask_agent_status

    expect(answer.keys.sort).to eq(keys)
    expect(response.body).not_to include('A shopper wrote this')
  end

  it 'answers a suspended account with its last state, which is disconnected' do
    connect_through_app
    stub_ai_removal
    remove_app

    ask_agent_status

    expect(response).to have_http_status(:ok)
    expect(answer).to include('state' => 'disconnected', 'inbox_ids' => [])
  end
end
