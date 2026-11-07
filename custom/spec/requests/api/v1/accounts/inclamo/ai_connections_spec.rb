# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe 'Inclamo AI agent connection API', type: :request do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/ai/connection" }

  before { resolve_ai_service_publicly }

  def body
    response.parsed_body
  end

  it 'shows an account that was never connected, with its inboxes and no bot' do
    email = create(:inbox, :with_email, account: account)
    create(:agent_bot_inbox, inbox: email, agent_bot: create(:agent_bot, account: account))

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(body).to include('connected' => false, 'state' => 'never_connected', 'connection' => nil, 'encryption_configured' => true)
    expect(body['get_agent_url']).to start_with('https://')
    inboxes = body['inboxes'].index_by { |inbox| inbox['id'] }
    expect(inboxes[website.id]).to include('selectable' => true, 'other_bot' => nil, 'connected' => false)
    expect(inboxes[email.id]).to include('selectable' => false, 'other_bot' => 'Agent Bot')
  end

  it 'connects with a code and answers the connection, never the token or the secret' do
    stub_ai_registration

    post path, params: { connection_code: ai_code, inbox_ids: [website.id] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(body).to include('connected' => true, 'state' => 'connected')
    expect(body['connection']).to include('state' => 'connected', 'inbox_ids' => [website.id], 'last_error' => nil)
    phone_id = body['connection']['phone_inbox_id']
    expect(body['inboxes'].pluck('id')).not_to include(phone_id)
    expect(body['inboxes'].find { |inbox| inbox['id'] == website.id }).to include('connected' => true, 'selectable' => true)
    bot = AgentBot.find(Inclamo::AiConnection.last.agent_bot_id)
    expect(response.body).not_to include(bot.access_token.token)
    expect(response.body).not_to include(bot.secret)
  end

  it 'says the code is not valid and asks the AI service nothing' do
    stub = stub_ai_registration

    post path, params: { connection_code: 'hello', inbox_ids: [website.id] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body['error']).to eq('invalid_code')
    expect(stub).not_to have_been_requested
  end

  it 'shows the AI service refusal in its own words' do
    stub_ai_registration(status: 410, body: { error: 'expired', message: 'This connection code has expired.' })

    post path, params: { connection_code: ai_code, inbox_ids: [website.id] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body).to include('error' => 'refused', 'message' => 'This connection code has expired.', 'service_error' => 'expired')
    expect(AgentBot.count).to eq(0)
  end

  it 'says the AI service did not answer' do
    stub_ai_registration(status: 502, body: {})

    post path, params: { connection_code: ai_code, inbox_ids: [website.id] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:bad_gateway)
    expect(body['error']).to eq('not_answered')
  end

  it 'disconnects and says whether the AI service was told' do
    connect_ai_agent(account, [website])
    stub_ai_removal

    delete path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(body).to include('connected' => false, 'state' => 'disconnected', 'ai_service_told' => true)
    expect(body['last_disconnection']).to include('ai_service_told' => true)
  end

  it "refuses the bot's token at once after disconnecting, and no message is added" do
    record = connect_ai_agent(account, [website])
    stub_ai_removal
    token = AgentBot.find(record.agent_bot_id).access_token.token
    conversation = create(:conversation, account: account, inbox: website)

    delete path, headers: admin.create_new_auth_token, as: :json
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'Still here' }, headers: { 'api_access_token' => token }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(conversation.messages.where(content: 'Still here')).to be_empty
  end

  it 'shows a failing connection with the time and kind of the last failure' do
    record = connect_ai_agent(account, [website])
    Inclamo::AiConnection.record_failure(record.id, 'http_503')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(body['connection']).to include('state' => 'failing', 'last_error' => 'http_503')
    expect(body['connection']['last_failed_at']).to be_present
  end

  it 'refuses an agent, to read, to connect and to disconnect' do
    stub = stub_ai_registration

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post path, params: { connection_code: ai_code, inbox_ids: [website.id] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    delete path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(stub).not_to have_been_requested
    expect(AgentBot.count).to eq(0)
  end

  it 'keeps the connection code out of the request log' do
    expect(Rails.application.config.filter_parameters).to include(:connection_code)
  end
end
