# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo order roles API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/order_roles" }

  def members
    response.parsed_body['members'].index_by { |member| member['user_id'] }
  end

  it 'lists the members with who may act; a new agent may not' do
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(members[admin.id]).to include('can_act' => true, 'switchable' => false, 'role' => 'administrator')
    expect(members[agent.id]).to include('can_act' => false, 'switchable' => true, 'granted_at' => nil)
  end

  it 'gives the role to an agent and takes it away' do
    post path, params: { user_id: agent.id }, headers: admin.create_new_auth_token, as: :json

    expect(members[agent.id]).to include('can_act' => true)
    expect(members[agent.id]['granted_at']).to be_present
    expect(Inclamo::OrderRole.last.granted_by).to eq(admin)

    delete "#{path}/#{agent.id}", headers: admin.create_new_auth_token, as: :json

    expect(members[agent.id]).to include('can_act' => false)
    expect(Inclamo::OrderRole.count).to eq(0)
  end

  it 'gives the role once, however often it is asked' do
    2.times { post path, params: { user_id: agent.id }, headers: admin.create_new_auth_token, as: :json }

    expect(Inclamo::OrderRole.count).to eq(1)
  end

  it 'does not reach a user of another account' do
    outsider = create(:user, account: create(:account), role: :agent)

    post path, params: { user_id: outsider.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Inclamo::OrderRole.count).to eq(0)
  end

  it 'refuses an agent who tries to give the role, to anyone' do
    post path, params: { user_id: agent.id }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(Inclamo::OrderRole.count).to eq(0)
  end

  it 'refuses an agent who tries to read or take the role' do
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), granted_by: admin)

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    delete "#{path}/#{agent.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Inclamo::OrderRole.count).to eq(1)
  end

  it 'tells each member what they may do, with the store connection' do
    Inclamo::OrderRole.create!(account_user: AccountUser.find_by(account: account, user: agent), granted_by: admin)

    get "/api/v1/accounts/#{account.id}/inclamo/shopify/connection", headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['viewer']).to eq('administrator' => false, 'can_act_on_orders' => true)
  end
end
