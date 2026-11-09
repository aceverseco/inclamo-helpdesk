# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo discount grants API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/discount_grants" }
  let(:membership) { AccountUser.find_by(account: account, user: agent) }

  def members
    response.parsed_body['members'].index_by { |member| member['user_id'] }
  end

  it 'lists who may give discounts; administrators always, a new agent not' do
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(members[admin.id]).to include('can_give' => true, 'switchable' => false)
    expect(members[agent.id]).to include('can_give' => false, 'switchable' => true, 'granted_at' => nil)
    expect(Inclamo::DiscountGrant.allows?(AccountUser.find_by(account: account, user: admin))).to be(true)
  end

  it 'gives the right and takes it away, apart from the order-actions role' do
    post path, params: { user_id: agent.id }, headers: admin.create_new_auth_token, as: :json

    expect(members[agent.id]).to include('can_give' => true)
    expect(Inclamo::DiscountGrant.allows?(membership)).to be(true)
    expect(Inclamo::OrderRole.allows?(membership)).to be(false)

    Inclamo::OrderRole.create!(account_user: membership, granted_by: admin)
    delete "#{path}/#{agent.id}", headers: admin.create_new_auth_token, as: :json

    expect(members[agent.id]).to include('can_give' => false)
    expect(Inclamo::DiscountGrant.allows?(membership)).to be(false)
    expect(Inclamo::OrderRole.allows?(membership)).to be(true)
  end

  it 'gives the right once, however often it is asked' do
    2.times { post path, params: { user_id: agent.id }, headers: admin.create_new_auth_token, as: :json }

    expect(Inclamo::DiscountGrant.count).to eq(1)
  end

  it 'refuses an agent, even one holding the right' do
    Inclamo::DiscountGrant.create!(account_user: membership, granted_by: admin)

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post path, params: { user_id: agent.id }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not reach a user of another account' do
    outsider = create(:user, account: create(:account), role: :agent)

    post path, params: { user_id: outsider.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Inclamo::DiscountGrant.count).to eq(0)
  end
end
