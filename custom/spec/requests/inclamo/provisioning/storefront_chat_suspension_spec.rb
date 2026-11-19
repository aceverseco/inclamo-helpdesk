# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

# Suspension needs no code of this capability: Chatwoot's own checks refuse the
# widget of a suspended account. These examples pin both checks (the widget
# page and the widget's API) on a provisioned account's storefront inbox.
RSpec.describe 'App storefront chat: a suspended account has no storefront chat', type: :request do
  include_context 'with app provisioning'

  before { provision }

  let(:account) { provisioned.account }
  let(:inbox) { storefront_inbox }
  let(:website_token) { inbox.channel.website_token }
  let(:contact_inbox) { create(:contact_inbox, contact: create(:contact, account: account, email: nil), inbox: inbox) }
  let(:visitor) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token }

  def open_widget_page(conversation_token = nil)
    get '/widget', params: { website_token: website_token, cw_conversation: conversation_token }.compact
    response
  end

  def write(text)
    post '/api/v1/widget/messages', headers: { 'X-Auth-Token' => visitor },
                                    params: { website_token: website_token, message: { content: text } }, as: :json
    response
  end

  def start_conversation(text)
    post '/api/v1/widget/conversations', headers: { 'X-Auth-Token' => visitor },
                                         params: { website_token: website_token, message: { content: text } }, as: :json
    response
  end

  def read_messages
    get '/api/v1/widget/messages', headers: { 'X-Auth-Token' => visitor }, params: { website_token: website_token }
    response
  end

  it 'has the widget page refuse the storefront token' do
    expect_widget_page_served(website_token)

    remove_app

    expect(open_widget_page).to have_http_status(:unauthorized)
    expect(response.body).to include('Account is suspended')
    expect(open_widget_page(visitor)).to have_http_status(:unauthorized)
    expect { open_widget_page }.to not_change(ContactInbox, :count).and not_change(Contact, :count)
  end

  it 'has the widget\'s API refuse the storefront token: no conversation, no message, nothing read' do
    expect(start_conversation('Before the suspension')).to have_http_status(:ok)

    remove_app

    expect { start_conversation('A new conversation') }.to not_change(Conversation, :count).and not_change(Message, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to include('Account is suspended')
    expect { write('One more message') }.to not_change(Message, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(read_messages).to have_http_status(:unauthorized)
  end

  it 'keeps the inbox, its token and its conversations while suspended' do
    start_conversation('Before the suspension')
    conversation = inbox.conversations.last

    expect { remove_app }.to not_change(Inbox, :count).and not_change(Conversation, :count).and not_change(Message, :count)

    expect(storefront_inbox).to eq(inbox)
    expect(inbox.channel.reload.website_token).to eq(website_token)
    expect(conversation.reload.messages.pluck(:content)).to include('Before the suspension')
  end

  it 'serves the same token again after restoration, with the earlier conversation reachable' do
    start_conversation('Before the suspension')
    conversation = inbox.conversations.last
    remove_app
    expect(open_widget_page(visitor)).to have_http_status(:unauthorized)

    provision
    expect(response.parsed_body['outcome']).to eq('restored')

    expect(open_widget_page(visitor)).not_to have_http_status(:unauthorized)
    expect_widget_page_served(website_token)
    expect(read_messages).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('content')).to include('Before the suspension')
    expect { write('After the store came back') }.to change { conversation.reload.messages.count }.by(1).and not_change(Conversation, :count)
    expect(response).to have_http_status(:ok)

    ask_chat_status
    expect(response.parsed_body).to include('state' => 'active', 'website_token' => website_token, 'inbox_id' => inbox.id)
  end
end
