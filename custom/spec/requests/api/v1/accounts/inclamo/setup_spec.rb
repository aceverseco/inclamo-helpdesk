# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Helpdesk setup', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/setup" }
  let(:headers) { admin.create_new_auth_token }

  def overview
    get path, headers: headers, as: :json
    response.parsed_body
  end

  def review(step)
    digest = overview['review_digests'][step]
    patch path, params: { step: step, digest: digest }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'offers setup before any conversation or channel exists without making external changes' do
    data = overview
    expect(data).to include('ready' => false, 'complete' => false, 'ai_connected' => false, 'order_actions' => [])
    expect(data['checks'].values).to all(eq(false))
    expect(Inclamo::SetupState.count).to eq(0)
    expect(Conversation.count).to eq(0)
  end

  it 'requires real store and channel prerequisites, ignoring browser booleans' do
    review('staff')
    review('ai')
    post "#{path}/complete", params: { store: true, channels: true }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    create(:inclamo_shopify_connection, account: account)
    post "#{path}/complete", headers: headers, as: :json
    expect(response.parsed_body.dig('checks', 'channels')).to be(false)
    expect(response).to have_http_status(:conflict)
  end

  it 'completes a human-operated helpdesk, retaining reviews across requests' do
    create(:inclamo_shopify_connection, account: account)
    create(:inbox, account: account)
    review('staff')
    expect(overview.dig('checks', 'staff')).to be(true)
    review('ai')
    post "#{path}/complete", headers: headers, as: :json
    expect(response.parsed_body).to include('complete' => true, 'ai_connected' => false, 'order_actions' => [])
  end

  it 'invalidates reviews and completion when the underlying settings change' do
    connection = create(:inclamo_shopify_connection, account: account)
    create(:inbox, account: account)
    agent
    review('staff')
    review('ai')
    post "#{path}/complete", headers: headers, as: :json
    expect(response.parsed_body['complete']).to be(true)
    Inclamo::ActionPermissions.set!(AccountUser.find_by(account: account, user: agent), 'address', true, by: admin)
    expect(overview.dig('checks', 'staff')).to be(false)
    expect(overview['complete']).to be(false)
    Inclamo::AiPolicy.create!(account: account, action: 'refund', mode: 'forbidden')
    expect(overview.dig('checks', 'ai')).to be(false)
    connection.update!(status: 'broken')
    expect(overview.dig('checks', 'store')).to be(false)
  end

  it 'rejects a stale review and cannot review an invented step' do
    digest = overview['review_digests']['staff']
    agent
    patch path, params: { step: 'staff', digest: digest }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    patch path, params: { step: 'store', digest: 'anything' }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'refuses staff and cannot write another account setup' do
    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{path}/complete", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    other = create(:account)
    patch "/api/v1/accounts/#{other.id}/inclamo/setup", params: { step: 'ai', digest: overview['review_digests']['ai'] }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Inclamo::SetupState.where(account: other)).to be_empty
  end
end
