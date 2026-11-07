# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::Ai::Disconnect do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:elsewhere) { create(:inbox, account: account, name: 'Not connected') }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let!(:token) { bot.access_token.token }

  before { resolve_ai_service_publicly }

  def disconnect
    described_class.call(account: account)
  end

  it 'hands every pending conversation of the connected inboxes to the team' do
    stub_ai_removal
    handled = create(:conversation, account: account, inbox: website)
    other = create(:conversation, account: account, inbox: elsewhere, status: :pending)
    expect(handled.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: bot.id)

    disconnect

    expect(handled.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    expect(handled.waiting_since).to be_present
    expect(other.reload.status).to eq('pending')
  end

  it 'removes the bot, its inbox links and its token at once, and marks the connection disconnected' do
    stub_ai_removal

    disconnect

    expect(AgentBot.exists?(bot.id)).to be(false)
    expect(AgentBotInbox.where(agent_bot_id: bot.id)).to be_empty
    expect(AccessToken.find_by(token: token)).to be_nil
    expect(website.reload.agent_bot).to be_nil
    expect(record.reload).to have_attributes(state: 'disconnected', disconnected_at: be_present, removal_error: nil)
  end

  it 'tells the AI service with the bot former token' do
    removal = stub_ai_removal

    disconnect

    expect(removal.with(headers: { 'Authorization' => "Bearer #{token}" })).to have_been_requested
  end

  it 'keeps the Phone inbox and the labels' do
    stub_ai_removal
    Inclamo::Ai::Labels.ensure_fixed!(account)

    disconnect

    expect(Inbox.exists?(record.phone_inbox_id)).to be(true)
    expect(account.labels.pluck(:title)).to include('inclamo_handover', 'inclamo_urgent')
  end

  it 'disconnects when the AI service cannot be reached, and notes it' do
    stub_request(:delete, "#{AiServiceStubs::AI_SERVICE_URL}/connections/conn-1").to_raise(Errno::ECONNREFUSED)

    disconnect

    expect(record.reload).to have_attributes(state: 'disconnected', removal_error: 'not_answered')
    expect(AgentBot.exists?(bot.id)).to be(false)
  end

  it 'makes a new conversation of the inbox open as before the connection' do
    stub_ai_removal

    disconnect

    expect(create(:conversation, account: account, inbox: website.reload).status).to eq('open')
  end

  it 'refuses an account that is not connected' do
    stub_ai_removal
    disconnect

    expect { disconnect }.to raise_error(Inclamo::Ai::Error::NotConnected)
  end
end
