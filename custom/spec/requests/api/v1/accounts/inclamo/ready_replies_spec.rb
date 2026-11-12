# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

# A ready saved reply sent the way an agent sends any reply: its order
# variables are filled by the reply-order-variables path.
RSpec.describe 'Inclamo ready saved replies', type: :request do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:shipped) { shopify_fixture('order_details_shipped')['order'] }

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    Inclamo::Shopify::ConversationOrder.new(conversation).mark!(shipped)
    stub_shopify_fixture(:order_details, 'order_details_shipped')
  end

  it 'the delivery reply carries the number and the tracking link of the tied, shipped order' do
    reply = account.canned_responses.find_by!(short_code: 'delivery-status')

    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: reply.content, message_type: 'outgoing' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    sent = conversation.messages.outgoing.last.content
    expect(sent).to include('#1002', 'https://example.com/track/E2Et001A')
    expect(sent).not_to include('{{')
  end
end
