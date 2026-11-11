# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# The AI agent's protected reply (ai-reply-ownership): docs/ai-connector.md §5.4.
RSpec.describe 'Inclamo AI agent protected reply', type: :request do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:website) { web_widget.inbox }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:bot_headers) { { 'api_access_token' => bot.access_token.token } }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: website) }
  let(:conversation) { create(:conversation, account: account, inbox: website, contact: contact, contact_inbox: contact_inbox) }

  before { create(:inbox_member, user: agent, inbox: website) }

  def reply_path(conv = conversation)
    "/api/v1/accounts/#{account.id}/inclamo/ai/conversations/#{conv.display_id}/reply"
  end

  def native_path(conv = conversation)
    "/api/v1/accounts/#{account.id}/conversations/#{conv.display_id}/messages"
  end

  def reply(content = 'We have your order.', conv: conversation, headers: bot_headers)
    post reply_path(conv), params: { content: content }, headers: headers, as: :json
  end

  def body
    response.parsed_body
  end

  describe 'while the conversation is Pending' do
    it 'posts the reply as the agent and answers its id' do
      reply

      expect(response).to have_http_status(:created)
      message = conversation.messages.find(body['id'])
      expect(message).to have_attributes(content: 'We have your order.', message_type: 'outgoing', private: false, sender: bot)
      expect(conversation.reload.status).to eq('pending')
    end

    it 'makes the same message, with the same events, as a reply through the native call' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      reply('Protected')
      protected_reply = conversation.messages.find(body['id'])
      post native_path, params: { content: 'Native' }, headers: bot_headers, as: :json
      native_reply = conversation.messages.where(content: 'Native').sole

      keys = %w[message_type private sender_type sender_id content_type content_attributes inbox_id account_id]
      expect(protected_reply.attributes.slice(*keys)).to eq(native_reply.attributes.slice(*keys))
      [protected_reply, native_reply].each do |message|
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, anything, hash_including(message: message))
      end
    end

    it 'renders Liquid in the text as a native reply does' do
      reply('Hello {{contact.name}}')
      protected_reply = conversation.messages.find(body['id'])
      post native_path, params: { content: 'Hello {{contact.name}}' }, headers: bot_headers, as: :json
      native_reply = conversation.messages.where.not(id: protected_reply.id).sole

      expect(protected_reply.content).to eq(native_reply.content)
      expect(protected_reply.content).to eq("Hello #{contact.name}")
    end

    it 'records when the agent last answered' do
      perform_enqueued_jobs(only: EventDispatcherJob) { reply }

      expect(record.reload.last_reply_at).to be_present
    end
  end

  describe 'once the conversation is not Pending' do
    it 'refuses after a person took the conversation, posting nothing' do
      Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: agent.id).perform

      expect { reply('Late') }.not_to(change { conversation.messages.count })
      expect(response).to have_http_status(:conflict)
      expect(body).to include('error' => 'conversation_not_pending', 'status' => 'open')
      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    end

    it 'refuses after a person replied publicly' do
      Messages::MessageBuilder.new(agent, conversation, ActionController::Parameters.new(content: 'I am here')).perform

      expect { reply('Late') }.not_to(change { conversation.messages.count })
      expect(response).to have_http_status(:conflict)
      expect(body['error']).to eq('conversation_not_pending')
    end

    it 'refuses in a conversation the agent handed over, or one that is resolved or snoozed' do
      conversation.bot_handoff!
      reply
      expect(response).to have_http_status(:conflict)

      %i[resolved snoozed].each do |status|
        other = create(:conversation, account: account, inbox: website, contact: contact, contact_inbox: contact_inbox)
        other.update!(status: status)
        reply(conv: other)
        expect(response).to have_http_status(:conflict)
        expect(body['status']).to eq(status.to_s)
      end
    end

    it 'does not record the refused reply as the time the agent answered' do
      conversation.bot_handoff!
      perform_enqueued_jobs(only: EventDispatcherJob) { reply }

      expect(record.reload.last_reply_at).to be_nil
    end
  end

  describe 'what is refused before the conversation is read' do
    it 'refuses a reply without text' do
      ['', '   ', nil].each do |content|
        expect { reply(content) }.not_to(change { conversation.messages.count })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to eq('empty_reply')
      end
    end

    it "refuses a user's token and the token of a disconnected account" do
      reply(headers: { 'api_access_token' => admin.access_token.token })
      expect(response).to have_http_status(:unauthorized)

      record.update!(state: 'disconnected')
      reply
      expect(response).to have_http_status(:unauthorized)
      expect(conversation.messages.count).to eq(0)
    end

    it 'refuses a conversation of another inbox, and one that does not exist, the same way' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))

      reply(conv: other)
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/accounts/#{account.id}/inclamo/ai/conversations/999999/reply", params: { content: 'x' }, headers: bot_headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(other.messages.count).to eq(0)
    end
  end
end
