# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# A person's take-over of a Pending conversation is committed with the
# person's own action (ai-reply-ownership, design D3), not later in a job.
RSpec.describe 'Taking a Pending conversation from the AI agent' do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:conversation) { create(:conversation, account: account, inbox: website) }
  let(:other_inbox) { create(:inbox, account: account) }

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
  end

  def message_by(sender, type: :outgoing, private: false, conv: conversation)
    attributes = { conversation: conv, account: account, inbox: conv.inbox, message_type: type, private: private, content: 'Text' }
    # An outgoing message without a sender (automation) needs the factory's trait.
    return create(:message, :bot_message, **attributes) if sender == :automation

    create(:message, sender: sender, **attributes)
  end

  def dispatched(event)
    have_received(:dispatch).with(event, anything, hash_including(conversation: conversation))
  end

  describe "a person's public reply" do
    it 'opens the conversation in the same transaction as the reply' do
      Message.transaction do
        message_by(agent)
        expect(Conversation.find(conversation.id).status).to eq('open')
      end

      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it "announces Chatwoot's hand-over and the status change once committed" do
      message_by(agent)

      expect(Rails.configuration.dispatcher).to dispatched(Events::Types::CONVERSATION_BOT_HANDOFF)
      expect(Rails.configuration.dispatcher).to dispatched(Events::Types::CONVERSATION_STATUS_CHANGED)
    end

    it 'leaves the conversation Pending on a private note, the agent, the shopper or automation' do
      message_by(agent, private: true)
      message_by(bot)
      message_by(conversation.contact, type: :incoming)
      message_by(:automation)

      expect(conversation.reload.status).to eq('pending')
    end

    it 'leaves a conversation of an inbox that is not connected, and a disconnected account, alone' do
      other = create(:conversation, account: account, inbox: other_inbox, status: :pending)
      message_by(agent, conv: other)
      expect(other.reload.status).to eq('pending')

      record.update!(state: 'disconnected')
      message_by(agent)
      expect(conversation.reload.status).to eq('pending')
    end

    it 'keeps the reply of a person in an Open conversation as it is' do
      conversation.update!(status: :open)

      expect { message_by(agent) }.to change(Message, :count).by(1)
      expect(Rails.configuration.dispatcher).not_to dispatched(Events::Types::CONVERSATION_BOT_HANDOFF)
    end
  end

  describe "a person's assignment" do
    it 'opens a Pending conversation in the same update, through the assignment service' do
      Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: agent.id).perform

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id, assignee_agent_bot_id: nil)
      expect(conversation.waiting_since).to be_present
    end

    it 'opens a Pending conversation without an AI assignee, which the service leaves Pending' do
      # An earlier hand-over cleared the AI assignee; the shopper reopens the
      # resolved conversation and it is the agent's again (message.rb:435-444).
      conversation.bot_handoff!
      conversation.update!(status: :resolved)
      message_by(conversation.contact, type: :incoming)
      expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: nil)

      Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: agent.id).perform

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
      expect(conversation.status_changed_at).to be_within(5.seconds).of(Time.current)
    end

    it 'opens it on an assignment made outside the service' do
      conversation.update!(assignee: agent)

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    end

    it 'leaves unassignment, a bot assignee, another inbox and a non-Pending conversation alone' do
      conversation.update!(assignee: nil)
      expect(conversation.reload.status).to eq('pending')

      Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: bot.id, assignee_type: 'AgentBot').perform
      expect(conversation.reload.status).to eq('pending')

      other = create(:conversation, account: account, inbox: other_inbox, status: :pending)
      other.update!(assignee: agent)
      expect(other.reload.status).to eq('pending')

      snoozed = create(:conversation, account: account, inbox: website)
      snoozed.update!(status: :snoozed)
      snoozed.update!(assignee: agent)
      expect(snoozed.reload.status).to eq('snoozed')
    end
  end
end
