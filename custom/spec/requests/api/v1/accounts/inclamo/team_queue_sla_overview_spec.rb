# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo team queues SLA overview API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:closed_inbox) { create(:inbox, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/team_queues/sla_overview" }
  let(:start) { Time.zone.parse('2026-11-13 12:00:00') }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def policy!
    Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 900, resolution_seconds: 86_400, created_at: start - 1.day)
  end

  # An open conversation created `ago` before `start`, labelled, with its timer.
  def conversation(labels:, ago: 0, in_inbox: inbox, timed: true, **attributes)
    made = create(:conversation, account: account, inbox: in_inbox, created_at: start - ago, **attributes)
    made.update_labels(labels)
    Inclamo::Sla::Timers.apply!(made) if timed
    made
  end

  def overview(as: admin, at: start)
    travel_to(at) { get path, headers: as.create_new_auth_token }
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  def queue(body, key)
    body['queues'].find { |one| one['key'] == key }
  end

  it 'counts the conversations of each visible queue as overdue, soon and other' do
    policy!
    2.times { conversation(labels: ['delivery'], ago: 20.minutes) }
    conversation(labels: ['delivery'], ago: 12.minutes)
    3.times { conversation(labels: ['delivery'], ago: 1.minute) }
    conversation(labels: ['delivery'], timed: false)
    conversation(labels: ['return'], ago: 20.minutes)

    body = overview

    expect(body['queues'].pluck('key')).to eq(%w[urgent ai_handover overdue delivery cancellation damage missing_parts return])
    expect(queue(body, 'delivery')).to include('name' => 'Delivery', 'total' => 7, 'overdue' => 2, 'soon' => 1, 'other' => 4, 'capped' => false)
    expect(queue(body, 'return')).to include('total' => 1, 'overdue' => 1, 'soon' => 0, 'other' => 0)
    expect(queue(body, 'damage')).to include('total' => 0, 'overdue' => 0, 'soon' => 0, 'other' => 0)
    expect(body).to include('policies' => true, 'cap' => 2_000)
  end

  it 'totals each conversation once, whatever number of queues lists it' do
    policy!
    both = conversation(labels: %w[delivery return], ago: 20.minutes)
    both.update!(priority: :urgent)
    conversation(labels: ['delivery'], ago: 20.minutes)
    conversation(labels: ['damage'], ago: 12.minutes)

    body = overview

    expect(queue(body, 'urgent')).to include('overdue' => 1)
    expect(queue(body, 'delivery')).to include('overdue' => 2)
    expect(queue(body, 'return')).to include('overdue' => 1)
    expect(body['totals']).to eq('overdue' => 2, 'soon' => 1)
  end

  it 'adds up to the count the list of queues shows for the same member' do
    policy!
    conversation(labels: ['delivery'], ago: 20.minutes)
    conversation(labels: ['delivery'], ago: 1.minute)
    conversation(labels: ['delivery'], ago: 20.minutes, in_inbox: closed_inbox)

    [admin, agent].each do |user|
      shown = queue(overview(as: user), 'delivery')
      travel_to(start) { get "/api/v1/accounts/#{account.id}/inclamo/team_queues", headers: user.create_new_auth_token }
      counted = response.parsed_body['queues'].find { |one| one['key'] == 'delivery' }['count']

      expect(shown['overdue'] + shown['soon'] + shown['other']).to eq(counted)
      expect(shown['total']).to eq(counted)
    end
  end

  it 'counts for an agent only the conversations of their inboxes' do
    policy!
    2.times { conversation(labels: ['return'], ago: 20.minutes) }
    conversation(labels: ['return'], ago: 20.minutes, in_inbox: closed_inbox)

    expect(queue(overview(as: agent), 'return')).to include('total' => 2, 'overdue' => 2)
    expect(queue(overview(as: admin), 'return')).to include('total' => 3, 'overdue' => 3)
  end

  it 'leaves out resolved conversations and a hidden queue' do
    policy!
    conversation(labels: ['damage'], ago: 20.minutes)
    conversation(labels: ['damage'], ago: 20.minutes, status: :resolved)
    Inclamo::TeamQueue.find_by(account_id: account.id, key: 'return').update!(hidden: true)

    body = overview

    expect(queue(body, 'damage')).to include('total' => 1, 'overdue' => 1)
    expect(queue(body, 'return')).to be_nil
  end

  it 'counts a replied conversation under other, and a stopped timer too' do
    kept = policy!
    replied = conversation(labels: ['cancellation'], ago: 20.minutes)
    Inclamo::SlaTimer.find_by(conversation_id: replied.id).update!(first_response_at: start - 18.minutes)
    conversation(labels: ['cancellation'], ago: 20.minutes)
    travel_to(start) { kept.destroy! }

    expect(queue(overview, 'cancellation')).to include('total' => 2, 'overdue' => 0, 'soon' => 0, 'other' => 2)
  end

  it 'moves a conversation from soon to overdue as its deadline passes' do
    policy!
    conversation(labels: ['delivery'], ago: 12.minutes)

    expect(queue(overview, 'delivery')).to include('soon' => 1, 'overdue' => 0)
    expect(queue(overview(at: start + 5.minutes), 'delivery')).to include('soon' => 0, 'overdue' => 1)
  end

  it 'says when the account has no SLA policy' do
    conversation(labels: ['delivery'], timed: false)

    body = overview

    expect(body['policies']).to be(false)
    expect(queue(body, 'delivery')).to include('total' => 1, 'overdue' => 0, 'soon' => 0, 'other' => 1)
  end

  it 'looks at the unmet timers of a queue only, so conversations with nothing to watch do not use up the limit' do
    policy!
    4.times { conversation(labels: ['delivery'], timed: false) }
    2.times { conversation(labels: ['delivery'], ago: 20.minutes) }
    stub_const('Inclamo::TeamQueues::SlaOverview::CAP', 2)

    expect(queue(overview, 'delivery')).to include('total' => 6, 'overdue' => 2, 'other' => 4, 'capped' => false)
  end

  it 'counts a queue with more unmet timers than the limit for that many, and says so' do
    policy!
    3.times { conversation(labels: ['delivery'], ago: 20.minutes) }
    stub_const('Inclamo::TeamQueues::SlaOverview::CAP', 2)

    expect(queue(overview, 'delivery')).to include('total' => 3, 'overdue' => 2, 'other' => 1, 'capped' => true)
  end

  it 'never shows a number below zero when the queue changes between its count and its timers' do
    policy!
    conversation(labels: ['delivery'], ago: 20.minutes)
    allow(Inclamo::TeamQueues::SlaOverview).to receive(:listed).and_wrap_original do |original, *arguments|
      _total, relation = original.call(*arguments)
      [0, relation]
    end

    expect(queue(overview, 'delivery')).to include('overdue' => 1, 'other' => 0)
  end

  it 'lists a queue Chatwoot cannot filter with unknown numbers, and counts the others' do
    policy!
    conversation(labels: ['delivery'], ago: 20.minutes)
    Inclamo::TeamQueue.find_by(account_id: account.id, key: 'damage').update!(query: { 'payload' => [{ 'attribute_key' => 'nonsense' }] })

    body = overview

    expect(queue(body, 'damage')).to include('total' => nil, 'overdue' => nil)
    expect(queue(body, 'delivery')).to include('overdue' => 1)
  end

  it 'keeps the answer for half a minute per member' do
    policy!
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    conversation(labels: ['delivery'], ago: 20.minutes)
    expect(queue(overview, 'delivery')['overdue']).to eq(1)

    conversation(labels: ['delivery'], ago: 20.minutes)

    expect(queue(overview(at: start + 20.seconds), 'delivery')['overdue']).to eq(1)
    expect(queue(overview(as: agent, at: start + 20.seconds), 'delivery')['overdue']).to eq(2)
    expect(queue(overview(at: start + 31.seconds), 'delivery')['overdue']).to eq(2)
  end

  it 'is closed without a session' do
    get path

    expect(response).to have_http_status(:unauthorized)
  end
end
