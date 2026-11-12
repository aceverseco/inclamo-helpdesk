# frozen_string_literal: true

require 'rails_helper'

# `sla-overdue`, the label behind the team queue "Overdue": on a conversation
# while a missed SLA target is still unmet.
RSpec.describe Inclamo::TeamQueues::Markers do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:timers) { Inclamo::Sla::Timers }
  let!(:policy) { Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 7_200, resolution_seconds: 172_800) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { timers.apply!(conversation) }

  after { Current.reset }

  def labels(conv = conversation)
    Conversation.find(conv.id).label_list
  end

  def reply(at:)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: agent, created_at: at)
  end

  def resolve!(at)
    conversation.reload.update!(status: :resolved)
    Inclamo::SlaListener.instance.conversation_resolved(Events::Base.new('conversation.resolved', at, conversation: conversation))
  end

  it 'is added with sla-missed, in one update, when the first response is missed' do
    updates = []
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, name, *rest, **data|
      updates << data[:changed_attributes] if name == Events::Types::CONVERSATION_UPDATED
      original.call(name, *rest, **data)
    end

    timers.check_due!(conversation.created_at + 3.hours)

    expect(labels).to contain_exactly('sla-missed', 'sla-overdue')
    expect(updates.count { |changes| changes&.key?('label_list') }).to eq(1)
  end

  it 'is taken off by the answer while the resolution is not missed; sla-missed stays' do
    timers.check_due!(conversation.created_at + 3.hours)

    timers.replied!(reply(at: conversation.created_at + 4.hours))

    expect(labels).to eq(['sla-missed'])
  end

  it 'is not added by an answer that came late before the check saw the miss' do
    timers.replied!(reply(at: conversation.created_at + 4.hours))

    expect(labels).to eq(['sla-missed'])
  end

  it 'stays after an answer once the resolution is missed, until the conversation is resolved' do
    timers.check_due!(conversation.created_at + 3.days)
    timers.replied!(reply(at: conversation.created_at + 3.days))
    expect(labels).to include('sla-overdue')

    resolve!(conversation.created_at + 4.days)

    expect(labels).to eq(['sla-missed'])
  end

  it 'is taken off on resolve when nobody ever answered' do
    timers.check_due!(conversation.created_at + 3.hours)

    resolve!(conversation.created_at + 4.hours)

    expect(labels).to eq(['sla-missed'])
  end

  it 'is taken off when the policy is deleted and its timer stops' do
    timers.check_due!(conversation.created_at + 3.hours)

    policy.destroy!

    expect(Inclamo::SlaTimer.find_by(conversation_id: conversation.id).stopped_at).to be_present
    expect(labels).to eq(['sla-missed'])
  end

  it 'is put back by the next pass after a person took it off while the target is still unmet' do
    timers.check_due!(conversation.created_at + 3.hours)
    conversation.reload.update_labels(['sla-missed'])

    timers.check_due!(conversation.created_at + 3.hours + 1.minute)

    expect(labels).to contain_exactly('sla-missed', 'sla-overdue')
  end

  it 'is taken off by the next pass where it is carried and nothing is overdue' do
    # As after a write that failed when the target was met, or a label added by hand.
    timers.check_due!(conversation.created_at + 3.hours)
    Inclamo::SlaTimer.where(conversation_id: conversation.id).update_all(first_response_at: conversation.created_at + 4.hours) # rubocop:disable Rails/SkipsModelValidations
    by_hand = create(:conversation, account: account, inbox: create(:inbox, account: account))
    by_hand.update_labels(%w[sla-overdue vip])
    resolved = create(:conversation, account: account, inbox: create(:inbox, account: account), status: :resolved)
    resolved.update_labels(['sla-overdue'])

    timers.check_due!(conversation.created_at + 5.hours)

    expect(labels).to eq(['sla-missed'])
    expect(labels(by_hand)).to eq(['vip'])
    expect(labels(resolved)).to be_empty
  end

  it 'brings a bounded number of conversations in step a run, oldest first, and goes on in the next' do
    others = 2.times.map { create(:conversation, account: account, inbox: inbox).tap { |conv| timers.apply!(conv) } }
    all = [conversation, *others]
    Inclamo::SlaTimer.where(conversation_id: all.map(&:id)).update_all(first_response_missed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    stale = 2.times.map { create(:conversation, account: account, inbox: inbox).tap { |conv| conv.update_labels(['sla-overdue']) } }

    described_class.reconcile_overdue(limit: 1)

    expect(all.map { |conv| labels(conv).include?('sla-overdue') }).to eq([true, false, false])
    expect(stale.map { |conv| labels(conv).include?('sla-overdue') }).to eq([false, true])

    2.times { described_class.reconcile_overdue(limit: 1) }

    expect(all.map { |conv| labels(conv).include?('sla-overdue') }).to eq([true, true, true])
    expect(stale.map { |conv| labels(conv).include?('sla-overdue') }).to eq([false, false])
    expect(described_class::RECONCILE_BATCH).to eq(200)
  end

  it 'is taken off when the policy is deleted, also when every target was already missed' do
    # "Standard" keeps to its own inbox, so the other inbox gets the policy with one target.
    policy.update!(all_inboxes: false, inbox_ids: [inbox.id])
    only_first = Inclamo::SlaPolicy.create!(account: account, name: 'First only', first_response_seconds: 600, all_inboxes: false,
                                            inbox_ids: [create(:inbox, account: account).id])
    other = create(:conversation, account: account, inbox_id: only_first.inbox_ids.first)
    timers.apply!(other)
    timers.check_due!(other.created_at + 1.hour)
    timer = Inclamo::SlaTimer.find_by(conversation_id: other.id)
    expect(timer).to have_attributes(policy_id: only_first.id, stopped_at: nil)
    expect(Inclamo::SlaTimer.running.where(id: timer.id)).to be_empty
    expect(labels(other)).to contain_exactly('sla-missed', 'sla-overdue')

    only_first.destroy!

    expect(timer.reload.stopped_at).to be_present
    expect(labels(other)).to eq(['sla-missed'])
    # Shown as missed still: deleting the policy does not change what happened.
    expect(Inclamo::Sla::TimerPresenter.new(timer).as_json.to_json).to include('"state":"missed"')
    timers.check_due!(other.created_at + 2.hours)
    expect(labels(other)).to eq(['sla-missed'])
  end

  it 'leaves a timer whose targets were all reached as it is when the policy is deleted' do
    timers.replied!(reply(at: conversation.created_at + 1.minute))
    conversation.reload.update!(status: :resolved)
    timers.resolved!(conversation, conversation.created_at + 2.minutes)

    policy.destroy!

    expect(Inclamo::SlaTimer.find_by(conversation_id: conversation.id).stopped_at).to be_nil
  end

  it 'is not put back on a resolved conversation, nor once the target is met' do
    answered = create(:conversation, account: account, inbox: inbox)
    timers.apply!(answered)
    timers.check_due!(conversation.created_at + 3.hours)
    create(:message, account: account, conversation: answered, inbox: inbox, message_type: :outgoing, sender: agent)
      .then { |message| timers.replied!(message) }
    resolve!(conversation.created_at + 4.hours)

    timers.check_due!(conversation.created_at + 5.hours)

    expect(labels).not_to include('sla-overdue')
    expect(labels(answered)).not_to include('sla-overdue')
  end

  it 'a pass with nothing to change updates no conversation' do
    timers.check_due!(conversation.created_at + 3.hours)
    # A conversation with no timer, and one whose label is already in step.
    untouched = create(:conversation, account: account, inbox: create(:inbox, account: account))
    before = [conversation, untouched].map { |conv| conv.reload.updated_at }
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    2.times { timers.check_due!(conversation.created_at + 3.hours + 1.minute) }
    2.times { described_class.sync_overdue(conversation.id) }

    expect([conversation, untouched].map { |conv| conv.reload.updated_at }).to eq(before)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_UPDATED, any_args)
  end

  it 'never fails the timer when the label cannot be written' do
    timers.check_due!(conversation.created_at + 3.hours)
    allow(described_class).to receive(:overdue?).and_raise(StandardError, 'no')

    expect { timers.replied!(reply(at: conversation.created_at + 4.hours)) }.not_to raise_error
    expect(Inclamo::SlaTimer.find_by(conversation_id: conversation.id).first_response_at).to be_present
  end
end
