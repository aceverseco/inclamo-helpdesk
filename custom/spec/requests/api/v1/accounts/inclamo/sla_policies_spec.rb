# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo SLA policies API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account, name: 'Chat') }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/sla_policies" }
  let(:standard) { { name: 'Standard', first_response_seconds: 7_200, resolution_seconds: 172_800, business_hours_only: false, all_inboxes: true } }

  def as_admin
    admin.create_new_auth_token
  end

  it 'creates a policy and lists it with its targets, next to the inboxes to choose from' do
    post path, params: standard, headers: as_admin, as: :json
    expect(response).to have_http_status(:created)

    get path, headers: as_admin, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['policies']).to contain_exactly(
      include('name' => 'Standard', 'first_response_seconds' => 7_200, 'resolution_seconds' => 172_800, 'all_inboxes' => true, 'position' => 0)
    )
    expect(response.parsed_body['inboxes']).to contain_exactly(include('id' => inbox.id, 'name' => 'Chat', 'business_hours' => false))
  end

  it 'refuses a policy without a target and says a target is needed' do
    post path, params: standard.merge(first_response_seconds: nil, resolution_seconds: nil), headers: as_admin, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['messages']).to include(I18n.t('inclamo.sla.errors.target_needed'))
    expect(Inclamo::SlaPolicy.count).to eq(0)
  end

  it 'covers chosen inboxes of the account only' do
    foreign = create(:inbox, account: create(:account))

    post path, params: standard.merge(all_inboxes: false, inbox_ids: [foreign.id]), headers: as_admin, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post path, params: standard.merge(all_inboxes: false, inbox_ids: [inbox.id]), headers: as_admin, as: :json
    expect(response.parsed_body['policy']).to include('all_inboxes' => false, 'inbox_ids' => [inbox.id])
  end

  it 'refuses a switch sent as null with 422 and a message, not a server error' do
    post path, params: standard.merge(business_hours_only: nil), headers: as_admin, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['messages']).to include(I18n.t('inclamo.sla.errors.business_hours_needed'))

    post path, params: standard.merge(all_inboxes: nil, inbox_ids: [inbox.id]), headers: as_admin, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['messages']).to include(I18n.t('inclamo.sla.errors.all_inboxes_needed'))
    expect(Inclamo::SlaPolicy.count).to eq(0)
  end

  it 'names the target that is too long' do
    post path, params: standard.merge(first_response_seconds: 400 * 86_400), headers: as_admin, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['messages']).to eq([I18n.t('inclamo.sla.errors.first_response_range')])
    expect(response.parsed_body['fields']).to eq(['first_response_seconds'])
  end

  it 'changes a policy, and a target can be cleared while the other stays' do
    policy = Inclamo::SlaPolicy.create!(standard.merge(account: account))

    patch "#{path}/#{policy.id}", params: { name: 'Fast', resolution_seconds: nil, business_hours_only: true }, headers: as_admin, as: :json

    expect(response).to have_http_status(:success)
    expect(policy.reload).to have_attributes(name: 'Fast', first_response_seconds: 7_200, resolution_seconds: nil, business_hours_only: true)
  end

  it 'reorders and deletes policies' do
    first = Inclamo::SlaPolicy.create!(standard.merge(account: account, name: 'First'))
    second = Inclamo::SlaPolicy.create!(standard.merge(account: account, name: 'Second'))

    post "#{path}/reorder", params: { ids: [second.id, first.id] }, headers: as_admin, as: :json
    expect(response.parsed_body['policies'].pluck('name')).to eq(%w[Second First])

    delete "#{path}/#{second.id}", headers: as_admin, as: :json
    expect(response).to have_http_status(:no_content)
    expect(Inclamo::SlaPolicy.pluck(:name)).to eq(['First'])
  end

  it 'does not reach a policy of another account' do
    foreign = Inclamo::SlaPolicy.create!(standard.merge(account: create(:account)))

    patch "#{path}/#{foreign.id}", params: { name: 'Mine' }, headers: as_admin, as: :json
    expect(response).to have_http_status(:not_found)
    delete "#{path}/#{foreign.id}", headers: as_admin, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.name).to eq('Standard')
  end

  it 'is closed to agents, for reading and for every change' do
    policy = Inclamo::SlaPolicy.create!(standard.merge(account: account))
    headers = agent.create_new_auth_token

    get path, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['message']).to eq(I18n.t('inclamo.sla.errors.forbidden'))
    post path, params: standard, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    patch "#{path}/#{policy.id}", params: { name: 'Agent' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{path}/reorder", params: { ids: [policy.id] }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    delete "#{path}/#{policy.id}", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    get "#{path}/summary", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(policy.reload.name).to eq('Standard')
  end

  describe 'the summary' do
    let!(:policy) { Inclamo::SlaPolicy.create!(standard.merge(account: account)) }

    def timer(**attributes)
      Inclamo::SlaTimer.create!({ conversation: create(:conversation, account: account, inbox: inbox), policy: policy, policy_name: policy.name,
                                  first_response_seconds: 7_200, resolution_seconds: 172_800, started_at: 1.day.ago }.merge(attributes))
    end

    it 'counts one met, one missed and one running timer of the last 7 days' do
      timer(first_response_at: 23.hours.ago, resolved_at: 20.hours.ago)
      timer(first_response_at: 20.hours.ago, first_response_missed_at: 22.hours.ago)
      timer
      timer(started_at: 10.days.ago, first_response_at: 10.days.ago)

      get "#{path}/summary", params: { days: 7 }, headers: as_admin

      expect(response).to have_http_status(:success)
      row = response.parsed_body['policies'].first
      expect(row).to include('id' => policy.id, 'name' => 'Standard', 'conversations' => 3)
      expect(row['first_response']).to eq('total' => 3, 'met' => 1, 'missed' => 1, 'running' => 1, 'met_percent' => 33)
      expect(row['resolution']).to eq('total' => 3, 'met' => 1, 'missed' => 0, 'running' => 2, 'met_percent' => 33)
    end

    it 'shows 2 conversations and 50 % for the first response after one met and one missed' do
      timer(first_response_at: 23.hours.ago)
      timer(first_response_missed_at: 22.hours.ago)

      get "#{path}/summary", params: { days: 7 }, headers: as_admin

      row = response.parsed_body['policies'].first
      expect(row['conversations']).to eq(2)
      expect(row['first_response']['met_percent']).to eq(50)
    end

    it 'covers 30 days on request, and lists a policy without conversations' do
      timer(started_at: 10.days.ago, first_response_at: 10.days.ago)

      get "#{path}/summary", params: { days: 30 }, headers: as_admin

      expect(response.parsed_body['days']).to eq(30)
      expect(response.parsed_body['policies'].first).to include('conversations' => 1)

      policy.update!(resolution_seconds: nil)
      Inclamo::SlaTimer.delete_all
      get "#{path}/summary", params: { days: 7 }, headers: as_admin
      expect(response.parsed_body['policies'].first).to include('conversations' => 0, 'first_response' => nil, 'resolution' => nil)
    end
  end
end
