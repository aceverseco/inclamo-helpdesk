# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::AiAgentListener do
  include AiServiceStubs

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:conversation) { create(:conversation, account: account, inbox: website) }

  def message_by(sender, type: :outgoing, private: false, conv: conversation)
    message = create(:message, conversation: conv, account: account, inbox: conv.inbox, message_type: type, sender: sender, private: private, content: 'Text')
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    message
  end

  def assign(user, conv: conversation)
    conv.update!(assignee: user)
    listener.assignee_changed(Events::Base.new('assignee.changed', Time.zone.now, conversation: conv.reload))
  end

  it 'starts a conversation of a connected inbox as pending, handled by the bot' do
    expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: bot.id)
  end

  it "opens a pending conversation on a person's public reply" do
    message_by(agent)

    expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
  end

  it 'opens a pending conversation when a person is assigned' do
    assign(agent)

    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
  end

  it 'leaves the conversation pending on a private note of the team' do
    message_by(agent, private: true)

    expect(conversation.reload.status).to eq('pending')
  end

  it "leaves the conversation pending on the agent's reply, and records when it answered" do
    reply = message_by(bot)

    expect(conversation.reload.status).to eq('pending')
    expect(record.reload.last_reply_at).to be_within(1.second).of(reply.created_at)
  end

  it "leaves the conversation pending on the shopper's message" do
    message_by(conversation.contact, type: :incoming)

    expect(conversation.reload.status).to eq('pending')
  end

  it 'does not touch a conversation of an inbox that is not connected' do
    other = create(:conversation, account: account, inbox: create(:inbox, account: account), status: :pending)

    message_by(agent, conv: other)
    assign(agent, conv: other)

    expect(other.reload.status).to eq('pending')
  end

  it 'does nothing once the account is disconnected' do
    pending = conversation
    record.update!(state: 'disconnected')

    message_by(agent, conv: pending)

    expect(pending.reload.status).to eq('pending')
  end

  it 'stays a fallback: after the take-over in the transaction it hands over nothing a second time' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    message_by(agent)
    message_by(agent)

    expect(conversation.reload.status).to eq('open')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: conversation)).once
  end

  it 'is one of the listeners of Chatwoot dispatcher' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end
end
