# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# Capability agent-inbox-selection: PATCH of the account's AI agent connection
# changes the inboxes the agent answers in (design D1, D6).
RSpec.describe 'Inclamo AI agent connection API: changing the inboxes', type: :request do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:email) { create(:inbox, account: account, name: 'Email') }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/ai/connection" }
  let(:told) { [] }

  before { resolve_ai_service_publicly }

  def body
    response.parsed_body
  end

  def save(inbox_ids, user: admin)
    patch path, params: { inbox_ids: inbox_ids }, headers: user.create_new_auth_token, as: :json
  end

  def links_of(record)
    AgentBotInbox.where(agent_bot_id: record.agent_bot_id).order(:inbox_id).pluck(:inbox_id)
  end

  # No answer of the address carries the bot's credentials.
  def expect_no_credentials(record)
    bot = AgentBot.find(record.agent_bot_id)
    expect(response.body).not_to include(bot.access_token.token)
    expect(response.body).not_to include(bot.secret)
  end

  context 'with a connection' do
    let!(:record) { connect_ai_agent(account, [website]) }

    it "answers the page's payload with the new inboxes, the connection otherwise as it was" do
      stub_ai_inbox_change(told: told)

      save([website.id, email.id])

      expect(response).to have_http_status(:ok)
      expect(body).to include('connected' => true, 'state' => 'connected')
      expect(body['connection']).to include('inbox_ids' => [website.id, email.id], 'phone_inbox_id' => record.phone_inbox_id, 'inbox_change_error' => nil)
      expect(body['connection']['connected_at']).to eq(record.reload.connected_at.as_json)
      expect(body['inboxes'].select { |inbox| inbox['connected'] }.pluck('id')).to eq([website.id, email.id])
      expect(told).to eq([[website.id, email.id]])
      expect_no_credentials(record)
    end

    it 'takes the ids as strings, and an empty list' do
      stub_ai_inbox_change(told: told)

      save([email.id.to_s])
      expect(response).to have_http_status(:ok)
      save([])

      expect(response).to have_http_status(:ok)
      expect(body['connection']['inbox_ids']).to eq([])
      expect(told).to eq([[email.id], []])
    end

    it 'refuses an agent of the team and asks the AI service nothing' do
      stub = stub_ai_inbox_change(told: told)

      save([website.id, email.id], user: agent)

      expect(response).to have_http_status(:forbidden)
      expect(body['error']).to eq('forbidden')
      expect(stub).not_to have_been_requested
      expect(links_of(record)).to eq([website.id])
    end

    it 'refuses a body that names no list, or something other than inbox ids' do
      stub = stub_ai_inbox_change(told: told)

      [{}, { inbox_ids: 'all' }, { inbox_ids: ['abc'] }, { inbox_ids: [website.id, -1] }, { inbox_ids: [{ id: website.id }] }].each do |params|
        patch path, params: params, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to eq('invalid_inbox')
      end
      expect(stub).not_to have_been_requested
    end

    it 'refuses an inbox of another account and the Phone inbox as invalid, and one with another bot as such' do
      stub = stub_ai_inbox_change(told: told)
      create(:agent_bot_inbox, inbox: email, agent_bot: create(:agent_bot, account: account))

      save([website.id, create(:inbox).id])
      expect([response.status, body['error']]).to eq([422, 'invalid_inbox'])
      save([record.phone_inbox_id])
      expect([response.status, body['error']]).to eq([422, 'invalid_inbox'])
      save([website.id, email.id])
      expect([response.status, body['error']]).to eq([422, 'inbox_has_bot'])
      expect(body['message']).to be_present

      expect(stub).not_to have_been_requested
      expect(links_of(record)).to eq([website.id])
    end

    it "shows the AI service's refusal in its own words" do
      stub_ai_inbox_change(status: 422, body: { error: 'plan_limit', message: 'One inbox on this plan.' }, told: told)

      save([website.id, email.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to eq('error' => 'refused', 'message' => 'One inbox on this plan.', 'service_error' => 'plan_limit')
      expect(links_of(record)).to eq([website.id])
    end

    it 'says the AI service cannot change inboxes, or did not answer' do
      stub_ai_inbox_change(status: 404, told: told)
      save([website.id, email.id])
      expect([response.status, body['error']]).to eq([422, 'change_unsupported'])
      expect(body['message']).to include('Disconnect and connect again')

      stub_ai_inbox_change(status: 503, told: told)
      save([website.id, email.id])
      expect([response.status, body['error']]).to eq([502, 'not_answered'])

      expect(links_of(record)).to eq([website.id])
      expect_no_credentials(record)
    end

    it 'is refused as busy while the connection is being changed' do
      stub = stub_ai_inbox_change(told: told)

      Inclamo::Ai.with_account_lock(account) { save([website.id, email.id]) }

      expect([response.status, body['error']]).to eq([409, 'busy'])
      expect(stub).not_to have_been_requested
    end

    it 'answers 500 when the change was not completed, and the next read says so' do
      stub_ai_inbox_change(told: told)
      allow(AgentBotInbox).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      save([website.id, email.id])

      expect([response.status, body['error']]).to eq([500, 'not_applied'])
      expect(told).to eq([[website.id, email.id], [website.id]])
      expect_no_credentials(record)
      get path, headers: admin.create_new_auth_token, as: :json
      expect(body['connection']).to include('inbox_ids' => [website.id], 'inbox_change_error' => 'not_applied')
    end

    it 'counts for each inbox the pending conversations whose AI assignee is the agent, and nothing else' do
      record.update!(inbox_ids: [website.id, email.id])
      create(:agent_bot_inbox, inbox: email, agent_bot_id: record.agent_bot_id)
      create_list(:conversation, 2, account: account, inbox: website)
      create(:conversation, account: account, inbox: email.reload)
      create(:conversation, account: account, inbox: website, status: :open, assignee: agent)
      reopened = create(:conversation, account: account, inbox: website)
      reopened.update!(ai_assignee: nil)
      create(:conversation, account: account, inbox: create(:inbox, account: account), status: :pending)

      get path, headers: admin.create_new_auth_token, as: :json

      counts = body['inboxes'].to_h { |inbox| [inbox['id'], inbox['pending_for_agent']] }
      expect(counts[website.id]).to eq(2)
      expect(counts[email.id]).to eq(1)
      expect(counts.except(website.id, email.id).values).to all(eq(0))
    end

    it "lists an inbox given the agent's bot behind the page as one that can be ticked, not as the agent's" do
      chat = create(:inbox, account: account, name: 'Chat')
      create(:agent_bot_inbox, inbox: chat, agent_bot_id: record.agent_bot_id)

      get path, headers: admin.create_new_auth_token, as: :json

      expect(body['connection']['inbox_ids']).to eq([website.id])
      expect(body['inboxes'].find { |inbox| inbox['id'] == chat.id }).to include('connected' => false, 'other_bot' => nil, 'selectable' => true)
    end

    it 'shows an inbox the team deleted as gone at once' do
      record.update!(inbox_ids: [website.id, email.id])
      create(:agent_bot_inbox, inbox: email, agent_bot_id: record.agent_bot_id)
      email.destroy!

      get path, headers: admin.create_new_auth_token, as: :json

      expect(body['connection']['inbox_ids']).to eq([website.id])
    end
  end

  it 'refuses an account that is not connected and creates nothing' do
    stub = stub_ai_inbox_change(told: told)

    expect { save([website.id]) }.not_to(change { [AgentBot.count, AgentBotInbox.count, Inbox.count, Inclamo::AiConnection.count] })

    expect([response.status, body['error']]).to eq([404, 'not_connected'])
    expect(stub).not_to have_been_requested
  end

  it 'gives every inbox a count of nought without a connection' do
    get path, headers: admin.create_new_auth_token, as: :json

    expect(body['inboxes'].pluck('pending_for_agent')).to all(eq(0))
    expect(body['connection']).to be_nil
  end
end
