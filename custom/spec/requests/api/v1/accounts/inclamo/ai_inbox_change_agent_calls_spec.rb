# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# Capability agent-inbox-selection: what the agent's own calls
# (docs/ai-connector.md §5) see after the inboxes were changed on the page.
RSpec.describe 'Inclamo AI agent endpoints after a change of the inboxes', type: :request do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:person) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:email) { create(:inbox, account: account, name: 'Email') }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:bot_headers) { { 'api_access_token' => bot.access_token.token } }

  before do
    resolve_ai_service_publicly
    stub_ai_inbox_change
  end

  def change_to(*inboxes)
    patch "/api/v1/accounts/#{account.id}/inclamo/ai/connection", params: { inbox_ids: inboxes.map(&:id) }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  # A fresh copy of the headers each time: Rails adds X-Http-Method-Override
  # to the hash it is given for a GET sent as JSON.
  def agent_call(verb, conversation, action, params = {})
    public_send(verb, "/api/v1/accounts/#{account.id}/inclamo/ai/conversations/#{conversation.display_id}/#{action}",
                params: params, headers: bot_headers.dup, as: :json)
    response
  end

  it 'holds a new conversation of an added inbox for the agent, which may read and answer it' do
    change_to(website, email)

    conversation = create(:conversation, account: account, inbox: email.reload)
    create(:message, conversation: conversation, account: account, inbox: email, message_type: :incoming, sender: conversation.contact, content: 'Where is my parcel?')

    expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: bot.id)
    expect(agent_call(:get, conversation, 'messages')).to have_http_status(:ok)
    expect(response.parsed_body['messages'].pluck('text')).to eq(['Where is my parcel?'])
    answer = agent_call(:post, conversation, 'reply', content: 'It is on its way.')
    expect(answer).to have_http_status(:created), answer.body
  end

  it 'refuses the history, labels, the protected reply and order proposals of a removed inbox, giving nothing' do
    conversation = create(:conversation, account: account, inbox: website)
    create(:message, conversation: conversation, account: account, inbox: website, message_type: :incoming, sender: conversation.contact, content: 'Private matter')
    expect(agent_call(:get, conversation, 'messages')).to have_http_status(:ok)

    change_to(email)

    expect(conversation.reload.status).to eq('open')
    [
      agent_call(:get, conversation, 'messages'),
      agent_call(:post, conversation, 'labels', add: ['inclamo_handover']),
      agent_call(:post, conversation, 'reply', content: 'Still here'),
      agent_call(:get, conversation, 'orders'),
      agent_call(:post, conversation, 'proposals', request_id: 'r-1', action_name: 'cancel', order_id: 'gid://shopify/Order/1')
    ].each do |answer|
      expect(answer).to have_http_status(:forbidden), "#{answer.request.path}: #{answer.body}"
      expect(answer.body).not_to include('Private matter')
    end
    expect(conversation.reload.label_list).to be_empty
    expect(conversation.messages.where(content: 'Still here')).to be_empty
    expect(Inclamo::AiProposal.where(conversation_id: conversation.id)).to be_empty
  end

  # Pinned for docs/ai-connector.md §1.4: Chatwoot reopens a resolved
  # conversation of an inbox with a bot as Pending (app/models/message.rb,
  # reopen_resolved_conversation), so one the team resolved before the inbox
  # was added comes back Pending when the shopper writes again, without the
  # agent as its AI assignee and with the person it had, and the agent may read it.
  it "brings a resolved conversation of an added inbox back as Pending when the shopper writes again" do
    resolved = create(:conversation, account: account, inbox: email, status: :open, assignee: person)
    resolved.update!(status: :resolved)

    change_to(website, email)
    create(:message, conversation: resolved, account: account, inbox: email, message_type: :incoming, sender: resolved.contact, content: 'One more question')

    expect(resolved.reload).to have_attributes(status: 'pending', assignee_id: person.id, assignee_agent_bot_id: nil)
    expect(agent_call(:get, resolved, 'messages')).to have_http_status(:ok)
  end
end
