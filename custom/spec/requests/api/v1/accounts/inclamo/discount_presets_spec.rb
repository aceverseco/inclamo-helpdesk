# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo discount presets API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/discount_presets" }
  let(:sorry) { { name: 'Sorry', kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer' } }

  def grant!(user)
    Inclamo::DiscountGrant.create!(account_user: AccountUser.find_by(account: account, user: user), granted_by: admin)
  end

  it 'lets an administrator add, change and remove presets' do
    post path, params: sorry, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    created = response.parsed_body['preset']
    expect(created).to include('name' => 'Sorry', 'kind' => 'percentage', 'value' => '10', 'expires_in_days' => 30, 'usage_limit' => 1, 'audience' => 'customer')

    patch "#{path}/#{created['id']}", params: { value: '15', expires_in_days: '' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['preset']).to include('value' => '15', 'expires_in_days' => nil)

    delete "#{path}/#{created['id']}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['presets']).to eq([])
    expect(Inclamo::DiscountPreset.count).to eq(0)
  end

  it 'names the fields of a preset outside the limits and saves nothing' do
    post path, params: sorry.merge(value: '120', usage_limit: 0), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid', 'fields' => { 'value' => ['less_than_or_equal_to'], 'usage_limit' => ['greater_than'] })
    expect(Inclamo::DiscountPreset.count).to eq(0)
  end

  it 'refuses an agent who tries to read or change the presets, even one who may give discounts' do
    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    grant!(agent)
    post path, params: sorry, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Inclamo::DiscountPreset.count).to eq(0)
  end

  it 'lets an agent who may give discounts read the presets' do
    Inclamo::DiscountPreset.create!(sorry.merge(account: account))
    grant!(agent)

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['presets'].pluck('name')).to eq(['Sorry'])
  end

  it 'does not reach a preset of another account' do
    other = Inclamo::DiscountPreset.create!(sorry.merge(account: create(:account)))

    patch "#{path}/#{other.id}", params: { value: '50' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(other.reload.value).to eq(10)
  end
end
