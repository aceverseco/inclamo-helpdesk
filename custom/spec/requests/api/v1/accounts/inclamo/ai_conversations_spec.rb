# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe 'Inclamo AI agent endpoints', type: :request do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:website) { web_widget.inbox }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:bot_headers) { { 'api_access_token' => bot.access_token.token } }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: website) }
  let(:conversation) { create(:conversation, account: account, inbox: website, contact: contact, contact_inbox: contact_inbox) }
  let(:widget_token) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: website.id }).generate_token }

  def path(conv = conversation, action = 'messages')
    "/api/v1/accounts/#{account.id}/inclamo/ai/conversations/#{conv.display_id}/#{action}"
  end

  def body
    response.parsed_body
  end

  # The shopper writes in the widget, through Chatwoot's own widget API.
  def shopper_writes(content, files: [])
    message = { content: content, timestamp: Time.current }
    message[:attachments] = files.map { |name| fixture_file_upload(Rails.root.join("spec/assets/#{name}"), 'image/png') } if files.any?
    post api_v1_widget_messages_url, params: { website_token: web_widget.website_token, message: message }, headers: { 'X-Auth-Token' => widget_token }
    expect(response).to have_http_status(:success)
  end

  describe 'who may call' do
    it 'answers the connected bot for a conversation of a connected inbox' do
      get path, headers: bot_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include('id' => conversation.display_id, 'status' => 'pending', 'inbox_id' => website.id)
    end

    it 'takes the token as a bearer token too' do
      get path, headers: { 'Authorization' => "Bearer #{bot.access_token.token}" }, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'refuses a conversation of another inbox, giving nothing' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      create(:message, conversation: other, account: account, inbox: other.inbox, content: 'Not for the agent')

      get path(other), headers: bot_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('Not for the agent')
    end

    it 'refuses a conversation that does not exist the same way' do
      get "/api/v1/accounts/#{account.id}/inclamo/ai/conversations/999999/messages", headers: bot_headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses another bot's token" do
      other_bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, inbox: create(:inbox, account: account), agent_bot: other_bot)

      get path, headers: { 'api_access_token' => other_bot.access_token.token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a user's token and a dashboard session" do
      get path, headers: { 'api_access_token' => admin.access_token.token }, as: :json
      expect(response).to have_http_status(:unauthorized)

      get path, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses the bot of a disconnected account' do
      record.update!(state: 'disconnected')

      get path, headers: bot_headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET messages' do
    before do
      conversation
      shopper_writes('The box came broken')
      shopper_writes('', files: ['avatar.png'])
      shopper_writes('And this one', files: ['avatar.png'])
      create(:message, conversation: conversation, account: account, inbox: website, message_type: :outgoing, sender: bot, content: 'Thank you, I see the photos.')
      create(:message, conversation: conversation, account: account, inbox: website, message_type: :outgoing, sender: admin, content: 'Internal: refund it',
                       private: true)
      create(:message, conversation: conversation, account: account, inbox: website, message_type: :outgoing, sender: admin, content: 'We will help.')
      create(:message, conversation: conversation, account: account, inbox: website, message_type: :activity, content: 'Conversation was marked open')
    end

    it 'gives the public messages oldest first with their roles and files, and not the note' do
      get path, headers: bot_headers, as: :json

      messages = body['messages']
      expect(messages.map { |m| [m['role'], m['text']] }).to eq(
        [['shopper', 'The box came broken'], ['shopper', ''], ['shopper', 'And this one'], ['agent', 'Thank you, I see the photos.'], ['team', 'We will help.']]
      )
      expect(response.body).not_to include('Internal: refund it')
      expect(response.body).not_to include('marked open')
      photo = messages[1]['files'].sole
      expect(photo).to include('file_type' => 'image', 'content_type' => 'image/png')
      expect(photo['file_size']).to be_positive
      expect(photo['url']).to be_present
      expect(messages[0]['files']).to eq([])
    end

    it 'counts the files the shopper sent in all the conversation' do
      get path(conversation, 'messages?limit=1'), headers: bot_headers, as: :json

      expect(body['shopper_files']).to eq(2)
      expect(body['messages'].map { |m| m['text'] }).to eq(['We will help.'])
    end

    it 'keeps the limit between one and a hundred' do
      get path(conversation, 'messages?limit=500'), headers: bot_headers, as: :json
      expect(body['messages'].size).to eq(5)

      get path(conversation, 'messages?limit=2'), headers: bot_headers, as: :json
      expect(body['messages'].map { |m| m['role'] }).to eq(%w[agent team])
    end
  end

  describe 'POST labels' do
    before do
      create(:label, account: account, title: 'vip')
      conversation.update!(label_list: ['vip'])
    end

    it "adds a label and keeps the team's" do
      post path(conversation, 'labels'), params: { add: ['inclamo_intent_test'] }, headers: bot_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body['labels']).to contain_exactly('vip', 'inclamo_intent_test')
      expect(conversation.reload.label_list).to contain_exactly('vip', 'inclamo_intent_test')
    end

    it 'creates a label the account lacks, with its description, so that it is shown' do
      post path(conversation, 'labels'), params: { add: ['inclamo_intent_return'] }, headers: bot_headers, as: :json

      label = account.labels.find_by(title: 'inclamo_intent_return')
      expect(label).to have_attributes(description: 'Set by the AI agent', color: Inclamo::Ai::LABEL_COLOR)
    end

    it 'adds a label already there only once' do
      2.times { post path(conversation, 'labels'), params: { add: %w[inclamo_handover inclamo_handover] }, headers: bot_headers, as: :json }

      expect(conversation.reload.label_list).to contain_exactly('vip', 'inclamo_handover')
    end

    it 'refuses names that are not the agent labels, and adds none of the request' do
      ['vip2', 'Inclamo_x', 'inclamo_', 'inclamo_a b', 'inclamo_ü'].each do |name|
        post path(conversation, 'labels'), params: { add: ['inclamo_ok', name] }, headers: bot_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity), "accepted #{name}"
        expect(body['error']).to eq('invalid_label')
      end
      expect(conversation.reload.label_list).to eq(['vip'])
      expect(account.labels.where(title: 'inclamo_ok')).to be_empty
    end

    it 'refuses an empty request and more than twenty names' do
      post path(conversation, 'labels'), params: { add: [] }, headers: bot_headers, as: :json
      expect(body['error']).to eq('no_labels')

      post path(conversation, 'labels'), params: { add: (1..21).map { |n| "inclamo_l#{n}" } }, headers: bot_headers, as: :json
      expect(body['error']).to eq('too_many_labels')
    end

    it 'refuses a conversation of another inbox' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))

      post path(other, 'labels'), params: { add: ['inclamo_handover'] }, headers: bot_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(other.reload.label_list).to be_empty
    end
  end
end
