# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo conversation SLA API', type: :request do
  let(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/conversations/#{conversation.display_id}/sla" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def apply(**attributes)
    Inclamo::SlaPolicy.create!({ account: account, name: 'Standard', first_response_seconds: 7_200, resolution_seconds: 172_800 }.merge(attributes))
    Inclamo::Sla::Timers.apply!(conversation)
  end

  # Seconds are whole: a moment the specs travel to has no fraction, the
  # conversation's creation has one, so a count may be one second short.
  def timer_shown(at = Time.current)
    travel_to(at) { get path, headers: agent.create_new_auth_token, as: :json }
    expect(response).to have_http_status(:success)
    response.parsed_body['timer']
  end

  it 'says there is no timer when no policy applied' do
    expect(timer_shown).to be_nil
    expect(response.parsed_body['pending']).to be(false)
  end

  it 'says a timer is on its way when a policy covers the conversation but has not been applied yet' do
    Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 7_200, created_at: conversation.created_at - 1.minute)

    expect(timer_shown).to be_nil
    expect(response.parsed_body['pending']).to be(true)

    Inclamo::Sla::Timers.apply!(conversation)
    expect(timer_shown).to include('policy_name' => 'Standard')
    expect(response.parsed_body['pending']).to be(false)
  end

  it 'shows a running timer with the time left to each target' do
    apply

    shown = timer_shown(conversation.created_at + 30.minutes)
    expect(shown).to include('policy_name' => 'Standard', 'stopped' => false)
    expect(shown['first_response']).to include('state' => 'running', 'target_seconds' => 7_200, 'remaining_seconds' => be_within(1).of(5_400), 'counting' => true)
    expect(shown['resolution']).to include('state' => 'running', 'remaining_seconds' => be_within(1).of(172_800 - 1_800))
  end

  it 'shows a timer paused outside business hours, with the full target left' do
    saturday = ActiveSupport::TimeZone['Europe/Berlin'].parse('2026-11-07 12:00')
    inbox.update!(working_hours_enabled: true, timezone: 'Europe/Berlin')
    travel_to(saturday) { conversation && apply(business_hours_only: true) }

    shown = timer_shown(saturday + 1.hour)
    expect(shown['first_response']).to include('state' => 'paused', 'remaining_seconds' => 7_200, 'counting' => false)
    expect(Time.zone.parse(shown['next_change_at'])).to eq(ActiveSupport::TimeZone['Europe/Berlin'].parse('2026-11-09 09:00'))
  end

  it 'shows a target met with the time it took' do
    apply
    answer = travel_to(conversation.created_at + 25.minutes) do
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: agent)
    end
    Inclamo::Sla::Timers.replied!(answer)

    shown = timer_shown(conversation.created_at + 1.hour)
    expect(shown['first_response']).to include('state' => 'met', 'took_seconds' => be_within(1).of(1_500), 'counting' => false)
    expect(shown['resolution']).to include('state' => 'running')
  end

  it 'shows a target missed and by how much' do
    apply
    Inclamo::Sla::Timers.check_due!(conversation.created_at + 2.hours + 1.minute)

    shown = timer_shown(conversation.created_at + 3.hours)
    expect(shown['first_response']).to include('state' => 'missed', 'over_seconds' => be_within(1).of(3_600), 'counting' => true)
  end

  it 'shows a missed target as missed before the check has marked it' do
    apply

    expect(timer_shown(conversation.created_at + 2.hours + 10.seconds)['first_response']).to include('state' => 'missed', 'over_seconds' => be_within(1).of(10))
  end

  it 'shows the running targets as stopped once the policy is deleted' do
    apply
    Inclamo::SlaPolicy.find_by(name: 'Standard').destroy!

    shown = timer_shown(conversation.created_at + 3.hours)
    expect(shown).to include('stopped' => true, 'next_change_at' => nil)
    expect(shown['first_response']).to include('state' => 'stopped', 'counting' => false)
  end

  it 'leaves out a target the policy does not set' do
    apply(resolution_seconds: nil)

    expect(timer_shown['resolution']).to be_nil
  end

  it 'is closed to an agent who may not see the conversation' do
    apply

    get path, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
