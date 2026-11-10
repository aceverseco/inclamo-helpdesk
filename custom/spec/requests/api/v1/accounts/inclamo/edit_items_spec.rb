# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo items edit API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:base) { "/api/v1/accounts/#{account.id}/inclamo/shopify" }
  let(:order) { shopify_fixture('order_details_partly_shipped')['order'] }
  let(:mug_line) { order.dig('lineItems', 'nodes').find { |line| line['title'].start_with?('E2E Tracked Mug') } }
  let(:edit) { { lines: [{ line_item_id: mug_line['id'], quantity: 1 }] } }
  let!(:connection) { create(:inclamo_shopify_connection, account: account) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Inclamo::Shopify::OrderReader.forget!(account.id)
    stub_shopify(:order_details, data: { order: order })
    stub_shopify_fixture(:order_edit_begin, 'order_edit_begin_partly_shipped')
    stub_shopify_fixture(:order_edit_set_quantity, 'order_edit_set_quantity_reduced')
    stub_shopify_fixture(:order_edit_commit, 'order_edit_commit_reduced')
  end

  def preview(as:)
    post "#{base}/conversations/#{conversation.display_id}/actions/edit_items_preview", params: { order_id: order['id'], params: edit },
                                                                                      headers: as.create_new_auth_token, as: :json
  end

  it 'answers the summary as the store calculates it' do
    preview(as: admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('difference' => 'due_back', 'amount' => '80.0', 'currency' => 'UAH',
                                            'total_before' => { 'amount' => '1745.9', 'currency' => 'UAH' })
  end

  it 'forbids the summary to an agent without the role, and the store is not called' do
    preview(as: agent)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include('error' => 'not_allowed')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'saves the edit and answers what is due back, for the refund dialog' do
    params = edit.merge(expected: { total_after: '1665.9', balance: '-80.0' })
    post "#{base}/conversations/#{conversation.display_id}/actions",
         params: { action_name: 'edit_items', action_id: 'action-edit-items-0001', order_id: order['id'], params: params },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('outcome' => 'accepted', 'action' => 'edit_items', 'order_number' => '#1421',
                                            'result' => { 'difference' => 'due_back', 'amount' => '80.0', 'currency' => 'UAH' })
  end

  it 'reports whether the connection can edit items, naming the missing permission' do
    get "#{base}/connection", headers: admin.create_new_auth_token
    expect(response.parsed_body['actions'].find { |action| action['name'] == 'edit_items' }).to include('available' => true)

    connection.update!(scopes: connection.scopes - %w[write_order_edits read_order_edits])
    get "#{base}/connection", headers: admin.create_new_auth_token
    expect(response.parsed_body['actions'].find { |action| action['name'] == 'edit_items' })
      .to include('available' => false, 'reason' => 'missing_scope', 'missing_scopes' => ['write_order_edits'])
  end
end
