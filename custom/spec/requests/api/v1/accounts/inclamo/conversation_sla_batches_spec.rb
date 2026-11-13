# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo conversation SLA batch API', type: :request do
  let(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:closed_inbox) { create(:inbox, account: account) }
  let(:first) { create(:conversation, account: account, inbox: inbox) }
  let(:second) { create(:conversation, account: account, inbox: inbox) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/conversation_slas" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def policy!(**attributes)
    Inclamo::SlaPolicy.create!({ account: account, name: 'Standard', first_response_seconds: 7_200, resolution_seconds: 172_800 }.merge(attributes))
  end

  def read(ids, as: agent, at: Time.current)
    travel_to(at) { get path, params: { ids: ids }, headers: as.create_new_auth_token }
    response.parsed_body
  end

  it 'gives the timers of several conversations in one answer, and nil for one without a timer' do
    policy!
    Inclamo::Sla::Timers.apply!(first)
    late = create(:conversation, account: account, inbox: inbox, created_at: 1.day.ago)

    body = read([first.display_id, late.display_id].join(','), at: first.created_at + 30.minutes)

    expect(response).to have_http_status(:success)
    expect(body['timers'].keys).to contain_exactly(first.display_id.to_s, late.display_id.to_s)
    expect(body['timers'][first.display_id.to_s]['first_response']).to include('state' => 'running', 'remaining_seconds' => be_within(1).of(5_400))
    expect(body['timers'][late.display_id.to_s]).to be_nil
    expect(body['pending']).to eq([])
  end

  it 'takes the ids as a list too' do
    read([first.display_id, second.display_id])

    expect(response.parsed_body['timers'].keys).to contain_exactly(first.display_id.to_s, second.display_id.to_s)
  end

  it 'answers for a conversation what the single read answers' do
    policy!
    Inclamo::Sla::Timers.apply!(first)
    at = first.created_at + 3.hours

    batch = read(first.display_id.to_s, at: at)['timers'][first.display_id.to_s]
    travel_to(at) { get "/api/v1/accounts/#{account.id}/inclamo/conversations/#{first.display_id}/sla", headers: agent.create_new_auth_token, as: :json }

    expect(batch).to eq(response.parsed_body['timer'])
    expect(batch['first_response']).to include('state' => 'missed')
  end

  it 'names the conversations whose timer is on its way' do
    policy!(created_at: 1.hour.ago)
    Inclamo::SlaTimer.where(conversation_id: [first.id, second.id]).delete_all
    Inclamo::Sla::Timers.apply!(second)

    body = read([first.display_id, second.display_id])

    expect(body['pending']).to eq([first.display_id])
    expect(body['timers'][second.display_id.to_s]).to include('policy_name' => 'Standard')
  end

  it 'leaves out a conversation of an inbox the agent is not a member of' do
    hidden = create(:conversation, account: account, inbox: closed_inbox)
    policy!(created_at: 1.hour.ago)
    Inclamo::Sla::Timers.apply!(hidden)

    expect(read([first.display_id, hidden.display_id])['timers'].keys).to eq([first.display_id.to_s])
    expect(read([first.display_id, hidden.display_id], as: admin)['timers'].keys).to contain_exactly(first.display_id.to_s, hidden.display_id.to_s)
  end

  it "leaves out another account's conversation, and ids that are not numbers" do
    other = create(:conversation, account: create(:account))
    # Display ids start at 1 in every account: ask for one this account does not have.
    missing = [first.display_id, other.display_id].max + 50

    body = read("#{first.display_id},#{missing},abc,-3")

    expect(response).to have_http_status(:success)
    expect(body['timers'].keys).to eq([first.display_id.to_s])
  end

  it 'refuses more than 100 ids' do
    read((1..101).to_a.join(','))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'too_many_ids', 'limit' => 100)
  end

  it 'answers nothing for no ids' do
    expect(read('')).to eq('timers' => {}, 'pending' => [])
  end

  it 'is closed without a session' do
    get path, params: { ids: first.display_id }

    expect(response).to have_http_status(:unauthorized)
  end
end
