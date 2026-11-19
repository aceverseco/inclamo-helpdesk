# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')
require Rails.root.join('custom/spec/support/ai_service_stubs')

# Capability agent-inbox-selection, design D10: a storefront chat inbox made
# again while the store's AI agent is connected gets the agent by itself
# (docs/app-storefront-chat.md §6, docs/ai-connector.md §1.4).
RSpec.describe 'App storefront chat: a storefront inbox made again gets the AI agent', type: :request do
  include_context 'with app provisioning'
  include AiServiceStubs

  let!(:account) { linked_account(name: 'Maple & Oak') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:told) { [] }

  before { resolve_ai_service_publicly }

  def bot_of(inbox)
    AgentBotInbox.find_by(inbox_id: inbox.id)&.agent_bot_id
  end

  # The team deleted the storefront inbox the store had, with the agent on it.
  def connected_and_deleted
    ask_for_chat
    first = storefront_inbox
    record = connect_ai_agent(account, [first]).tap { |connection| connection.update!(connected_via: 'app') }
    first.destroy!
    record
  end

  it 'gives the new inbox to the agent and tells the AI service the new list once' do
    record = connected_and_deleted
    stub_ai_inbox_change(told: told)

    ask_for_chat

    inbox = storefront_inbox
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['outcome']).to eq('created')
    expect(bot_of(inbox)).to eq(record.agent_bot_id)
    expect(told).to eq([[inbox.id]])
    expect(record.reload).to have_attributes(inbox_ids: [inbox.id], inbox_change_error: nil)
    expect(create(:conversation, account: account, inbox: inbox.reload)).to have_attributes(status: 'pending', assignee_agent_bot_id: record.agent_bot_id)
  end

  it 'adds the new inbox to the inboxes the agent has' do
    email = create(:inbox, account: account, name: 'Email')
    record = connected_and_deleted
    AgentBotInbox.create!(inbox: email, agent_bot_id: record.agent_bot_id)
    record.update!(inbox_ids: [email.id] + record.inbox_ids)
    stub_ai_inbox_change(told: told)

    ask_for_chat

    expect(told).to eq([[email.id, storefront_inbox.id]])
    expect(record.reload.inbox_ids).to eq([email.id, storefront_inbox.id])
  end

  {
    'refuses' => { status: 422, body: { error: 'plan_limit', message: 'One inbox on this plan.' } },
    'does not know the call' => { status: 404, body: '' },
    'does not answer' => { status: 503, body: '' }
  }.each do |what, answer|
    it "makes the inbox for the team and says so on the AI agent page when the AI service #{what}" do
      record = connected_and_deleted
      stub_ai_inbox_change(**answer, told: told)

      ask_for_chat

      inbox = storefront_inbox
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['outcome']).to eq('created')
      expect(inbox).to be_present
      expect(bot_of(inbox)).to be_nil
      expect(told).to eq([[inbox.id]])
      expect(record.reload).to have_attributes(state: 'connected', answering_inbox_ids: [], inbox_change_error: 'storefront_not_added')
      expect(create(:conversation, account: account, inbox: inbox.reload).status).to eq('open')

      get "/api/v1/accounts/#{account.id}/inclamo/ai/connection", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('connection', 'inbox_change_error')).to eq('storefront_not_added')
    end
  end

  it 'makes the inbox for the team when another change of the connection is under way' do
    record = connected_and_deleted
    stub = stub_ai_inbox_change(told: told)

    Inclamo::Ai.with_account_lock(account) { ask_for_chat }

    expect(response).to have_http_status(:created)
    expect(bot_of(storefront_inbox)).to be_nil
    expect(stub).not_to have_been_requested
    expect(record.reload.inbox_change_error).to eq('storefront_not_added')
  end

  it 'asks nothing when the agent is not connected' do
    stub = stub_ai_inbox_change(told: told)

    ask_for_chat
    storefront_inbox.destroy!
    ask_for_chat

    expect(response).to have_http_status(:created)
    expect(bot_of(storefront_inbox)).to be_nil
    expect(stub).not_to have_been_requested
  end

  it 'asks nothing when the store already has its storefront inbox' do
    ask_for_chat
    connect_ai_agent(account, [])
    stub = stub_ai_inbox_change(told: told)

    ask_for_chat

    expect(response.parsed_body['outcome']).to eq('existed')
    expect(bot_of(storefront_inbox)).to be_nil
    expect(stub).not_to have_been_requested
  end

  it 'gives no other new inbox to the agent' do
    record = connect_ai_agent(account, [])
    stub = stub_ai_inbox_change(told: told)

    email = create(:inbox, account: account, name: 'Email')

    expect(bot_of(email)).to be_nil
    expect(stub).not_to have_been_requested
    expect(record.reload.inbox_ids).to eq([])
    expect(create(:conversation, account: account, inbox: email.reload).status).to eq('open')
  end
end
