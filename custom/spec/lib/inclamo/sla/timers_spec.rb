# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Sla::Timers do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  after { Current.reset }

  def policy(**attributes)
    Inclamo::SlaPolicy.create!({ account: account, name: 'Standard', first_response_seconds: 7_200, resolution_seconds: 172_800 }.merge(attributes))
  end

  def new_conversation(in_inbox = inbox)
    create(:conversation, account: account, inbox: in_inbox)
  end

  def reply(conversation, **attributes)
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :outgoing, sender: agent, **attributes)
  end

  def timer_of(conversation)
    Inclamo::SlaTimer.find_by(conversation_id: conversation.id)
  end

  def notes(conversation)
    conversation.messages.where(private: true).order(:id).pluck(:content)
  end

  describe 'applying a policy to a new conversation' do
    it 'applies a policy for all inboxes, from the moment the conversation was created' do
      standard = policy
      conversation = new_conversation

      described_class.apply!(conversation)

      expect(timer_of(conversation)).to have_attributes(policy_id: standard.id, policy_name: 'Standard', first_response_seconds: 7_200,
                                                        resolution_seconds: 172_800, started_at: be_within(1.second).of(conversation.created_at))
    end

    it 'applies a policy for chosen inboxes to those inboxes only' do
      policy(all_inboxes: false, inbox_ids: [inbox.id])
      covered = new_conversation
      elsewhere = new_conversation(create(:inbox, account: account))

      [covered, elsewhere].each { |conversation| described_class.apply!(conversation) }

      expect(timer_of(covered)).to be_present
      expect(timer_of(elsewhere)).to be_nil
    end

    it 'gives no timer when no policy covers the inbox' do
      conversation = new_conversation

      expect(described_class.apply!(conversation)).to be_nil
      expect(timer_of(conversation)).to be_nil
    end

    it 'applies the first covering policy in the list' do
      first = policy(name: 'First')
      second = policy(name: 'Second', all_inboxes: false, inbox_ids: [inbox.id])
      described_class.apply!(before_reorder = new_conversation)

      Inclamo::SlaPolicy.reorder!(account, [second.id, first.id])
      described_class.apply!(after_reorder = new_conversation)

      expect(timer_of(before_reorder).policy_name).to eq('First')
      expect(timer_of(after_reorder).policy_name).to eq('Second')
    end

    it 'gives no timer to a conversation created before the policy' do
      conversation = new_conversation
      travel_to(1.minute.from_now) do
        policy
        described_class.apply!(conversation)
      end

      expect(timer_of(conversation)).to be_nil
    end

    it 'counts a reply that was there before the timer was applied' do
      policy
      conversation = new_conversation
      answer = reply(conversation)

      described_class.apply!(conversation)

      expect(timer_of(conversation).first_response_at).to be_within(1.second).of(answer.created_at)
    end

    it "counts the resolution of a conversation Chatwoot creates resolved, a blocked contact's, which has no event" do
      policy
      contact = create(:contact, account: account, blocked: true)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                           contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox))
      expect(conversation).to be_resolved

      described_class.apply!(conversation)
      described_class.check_due!(conversation.created_at + 3.days)

      timer = timer_of(conversation)
      expect(timer.resolved_at).to be_within(1.second).of(conversation.created_at)
      expect(timer.resolution_missed_at).to be_nil
      expect(notes(conversation)).not_to include(a_string_including('resolution target'))
    end

    it 'counts a resolution whose event was handled before the timer existed' do
      policy
      conversation = new_conversation
      conversation.update!(status: :resolved)
      described_class.resolved!(conversation, Time.current)
      expect(timer_of(conversation)).to be_nil

      described_class.apply!(conversation)

      expect(timer_of(conversation).resolved_at).to be_within(1.second).of(conversation.reload.updated_at)
      expect(timer_of(conversation).resolution_missed_at).to be_nil
    end
  end

  describe 'the first human reply and the first resolution' do
    let!(:standard) { policy }
    let(:conversation) { new_conversation }

    before { described_class.apply!(conversation) }

    it 'stops the first-response timer on an agent\'s public reply, and the resolution timer keeps running' do
      described_class.replied!(reply(conversation, private: true))
      expect(timer_of(conversation).first_response_at).to be_nil

      answer = reply(conversation)
      described_class.replied!(answer)

      timer = timer_of(conversation)
      expect(timer.first_response_at).to be_within(1.second).of(answer.created_at)
      expect(timer.resolved_at).to be_nil
      expect(timer.first_response_missed_at).to be_nil
    end

    it "does not stop the first-response timer on a rule's message or a bot's message" do
      rule = create(:automation_rule, account: account, actions: [{ 'action_name' => 'send_message', 'action_params' => ['We got your message'] }])
      AutomationRules::ActionService.new(rule, account, conversation).perform
      described_class.replied!(conversation.messages.outgoing.last)
      described_class.replied!(reply(conversation, sender: create(:agent_bot, account: account)))

      expect(timer_of(conversation).first_response_at).to be_nil
    end

    it 'keeps the first reply when more follow' do
      first = reply(conversation)
      described_class.replied!(first)
      travel_to(10.minutes.from_now) { described_class.replied!(reply(conversation)) }

      expect(timer_of(conversation).first_response_at).to be_within(1.second).of(first.created_at)
    end

    it 'stops the resolution timer on the first resolution only' do
      resolved = 1.hour.from_now
      described_class.resolved!(conversation, resolved)
      described_class.resolved!(conversation, 2.hours.from_now)

      expect(timer_of(conversation).resolved_at).to be_within(1.second).of(resolved)
      expect(timer_of(conversation).resolution_missed_at).to be_nil
    end

    it 'marks a target reached after it passed as missed, once, before the check sees it' do
      late = travel_to(conversation.created_at + 3.hours) { reply(conversation) }
      described_class.replied!(late)
      described_class.check_due!(conversation.created_at + 3.hours)

      timer = timer_of(conversation)
      expect(timer.first_response_missed_at).to be_within(1.second).of(timer.started_at + 2.hours)
      expect(conversation.reload.label_list).to eq([Inclamo::Sla::LABEL])
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])
    end
  end

  describe 'the periodic check' do
    let!(:standard) { policy }
    let(:conversation) { new_conversation }

    before { described_class.apply!(conversation) }

    it 'marks nothing before a target passes' do
      described_class.check_due!(conversation.created_at + 119.minutes)

      expect(timer_of(conversation).first_response_missed_at).to be_nil
      expect(conversation.reload.label_list).to be_empty
    end

    it 'marks a missed first response once, with the label and a private note; a second run adds nothing' do
      travel_to(conversation.created_at + 2.hours + 1.minute) do
        described_class.check_due!
        described_class.check_due!
        Inclamo::SlaCheckJob.perform_now
      end

      timer = timer_of(conversation)
      expect(timer.first_response_missed_at).to be_within(1.second).of(timer.started_at + 2.hours)
      expect(timer.resolution_missed_at).to be_nil
      expect(conversation.reload.label_list).to contain_exactly(Inclamo::Sla::LABEL, Inclamo::TeamQueues::OVERDUE_LABEL)
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])
      expect(account.labels.find_by(title: Inclamo::Sla::LABEL)).to have_attributes(show_on_sidebar: true)
    end

    it 'marks a missed resolution when the conversation is still open, and keeps one label' do
      described_class.check_due!(conversation.created_at + 2.days + 1.minute)

      timer = timer_of(conversation)
      expect(timer.resolution_missed_at).to be_within(1.second).of(timer.started_at + 2.days)
      expect(conversation.reload.label_list).to contain_exactly(Inclamo::Sla::LABEL, Inclamo::TeamQueues::OVERDUE_LABEL)
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.',
                                         'SLA "Standard": the resolution target of 2 days was missed.'])
    end

    it 'keeps a missed target missed when the reply comes later' do
      described_class.check_due!(conversation.created_at + 3.hours)
      described_class.replied!(travel_to(conversation.created_at + 4.hours) { reply(conversation) })

      timer = timer_of(conversation)
      expect(timer.first_response_missed_at).to be_present
      expect(timer.first_response_at).to be_present
      expect(notes(conversation).size).to eq(1)
    end

    it 'marks nothing for targets reached in time' do
      described_class.replied!(reply(conversation))
      described_class.resolved!(conversation, Time.current)
      described_class.check_due!(conversation.created_at + 3.days)

      expect(timer_of(conversation)).to have_attributes(first_response_missed_at: nil, resolution_missed_at: nil)
      expect(notes(conversation)).to be_empty
    end

    it 'leaves an account label of the same name as it is' do
      account.labels.create!(title: Inclamo::Sla::LABEL, color: '#000000')

      described_class.check_due!(conversation.created_at + 3.hours)

      expect(account.labels.where(title: Inclamo::Sla::LABEL).pluck(:color)).to eq(['#000000'])
      expect(conversation.reload.label_list).to contain_exactly(Inclamo::Sla::LABEL, Inclamo::TeamQueues::OVERDUE_LABEL)
    end
  end

  describe 'the periodic check, when Chatwoot\'s events are late' do
    let!(:standard) { policy }
    let(:conversation) { new_conversation }
    let(:deadline) { timer_of(conversation).started_at + 2.hours }

    before { described_class.apply!(conversation) }

    it 'counts a reply sent in time that its event has not recorded yet as met, and marks nothing' do
      answer = travel_to(deadline - 2.seconds) { reply(conversation) }

      described_class.check_due!(deadline + 5.seconds)
      described_class.replied!(answer)

      timer = timer_of(conversation)
      expect(timer.first_response_at).to be_within(1.second).of(answer.created_at)
      expect(timer.first_response_missed_at).to be_nil
      expect(conversation.reload.label_list).to be_empty
      expect(Inclamo::Sla::TimerPresenter.new(timer, now: deadline + 1.minute).as_json[:first_response]).to include(state: 'met')
    end

    it 'counts a late reply its event has not recorded yet as missed, once' do
      late = travel_to(deadline + 30.seconds) { reply(conversation) }

      described_class.check_due!(deadline + 40.seconds)
      described_class.replied!(late)

      expect(timer_of(conversation).first_response_missed_at).to be_within(1.second).of(deadline)
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])
    end

    it 'does not mark a target reached after the check read the timer' do
      stale = Inclamo::SlaTimer.find(timer_of(conversation).id)
      described_class.replied!(travel_to(deadline - 1.second) { reply(conversation) })

      described_class.missed!(stale, 'first_response', deadline)

      expect(timer_of(conversation).first_response_missed_at).to be_nil
      expect(notes(conversation)).to be_empty
    end

    describe 'a resolution its event has not recorded yet' do
      let(:resolution_deadline) { timer_of(conversation).started_at + 2.days }

      before do
        described_class.replied!(reply(conversation))
        travel_to(resolution_deadline - 1.minute) { conversation.update!(status: :resolved) }
      end

      it 'is left to that event, which carries its moment' do
        described_class.check_due!(resolution_deadline + 1.minute)
        expect(timer_of(conversation)).to have_attributes(resolved_at: nil, resolution_missed_at: nil)

        described_class.resolved!(conversation, resolution_deadline - 1.minute)
        expect(timer_of(conversation)).to have_attributes(resolved_at: be_within(1.second).of(resolution_deadline - 1.minute),
                                                          resolution_missed_at: nil)
        expect(notes(conversation)).to be_empty
      end

      it 'is recorded at the conversation\'s last change when the event never comes' do
        described_class.check_due!(resolution_deadline + 11.minutes)

        expect(timer_of(conversation)).to have_attributes(resolved_at: be_within(1.second).of(resolution_deadline - 1.minute),
                                                          resolution_missed_at: nil)
        expect(notes(conversation)).to be_empty
      end
    end

    it 'goes on with the other timers when one cannot be marked, and marks that one on the next run' do
      other = new_conversation
      described_class.apply!(other)
      broken = timer_of(conversation).conversation_id
      allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, user, record, params|
        raise ActiveRecord::RecordInvalid if record.id == broken

        original.call(user, record, params)
      end

      described_class.check_due!(deadline + 1.minute)

      expect(timer_of(other).first_response_missed_at).to be_present
      expect(notes(other)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])
      expect(timer_of(conversation).first_response_missed_at).to be_nil
      expect(conversation.reload.label_list).to be_empty

      allow(Messages::MessageBuilder).to receive(:new).and_call_original
      described_class.check_due!(deadline + 2.minutes)

      expect(timer_of(conversation).first_response_missed_at).to be_within(1.second).of(deadline)
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])
    end
  end

  describe 'counting business hours only' do
    # Saturday noon in Berlin: the inbox is closed until Monday 9:00.
    let(:saturday) { ActiveSupport::TimeZone['Europe/Berlin'].parse('2026-11-07 12:00') }

    it 'does not count the closed weekend' do
      inbox.update!(working_hours_enabled: true, timezone: 'Europe/Berlin')
      travel_to(saturday) do
        policy(business_hours_only: true)
        described_class.apply!(@conversation = new_conversation)
      end

      described_class.check_due!(saturday + 1.day)
      expect(timer_of(@conversation).first_response_missed_at).to be_nil

      described_class.check_due!(saturday + 2.days + 0.5.hours) # Monday 12:30, two and a half hours open
      expect(timer_of(@conversation).first_response_missed_at).to eq(ActiveSupport::TimeZone['Europe/Berlin'].parse('2026-11-09 11:00'))
    end

    it 'leaves the timer alone until its deadline, unless the business hours change' do
      monday_eleven = ActiveSupport::TimeZone['Europe/Berlin'].parse('2026-11-09 11:00')
      travel_to(saturday - 1.hour) { inbox.update!(working_hours_enabled: true, timezone: 'Europe/Berlin') }
      travel_to(saturday) do
        policy(business_hours_only: true)
        described_class.apply!(@conversation = new_conversation)
      end
      timer = timer_of(@conversation)
      expect(timer.first_response_due_at).to eq(monday_eleven)

      expect(Inclamo::SlaTimer.maybe_due(saturday + 1.day)).to be_empty
      expect(Inclamo::SlaTimer.maybe_due(monday_eleven)).to eq([timer])

      # Open on Sundays from now on: the deadline moves, and the check works it out again.
      travel_to(saturday + 1.day) { inbox.working_hours.find_by(day_of_week: 0).update!(closed_all_day: false, open_all_day: true) }
      expect(Inclamo::SlaTimer.maybe_due(saturday + 1.day + 1.minute)).to eq([timer])
      sunday_two = ActiveSupport::TimeZone['Europe/Berlin'].parse('2026-11-08 02:00')
      travel_to(saturday + 1.day + 2.minutes) { described_class.check_due!(saturday + 1.day + 2.minutes) }
      expect(timer_of(@conversation).first_response_missed_at).to eq(sunday_two)
    end
  end

  describe 'deleting a policy' do
    let!(:standard) { policy }
    let(:conversation) { new_conversation }

    before { described_class.apply!(conversation) }

    it 'stops its running timers, which are not marked as missed later' do
      standard.destroy!

      timer = timer_of(conversation)
      expect(timer).to have_attributes(policy_id: nil, policy_name: 'Standard')
      expect(timer.stopped_at).to be_present

      described_class.check_due!(conversation.created_at + 3.days)
      described_class.replied!(reply(conversation))
      expect(timer.reload).to have_attributes(first_response_missed_at: nil, resolution_missed_at: nil, first_response_at: nil)
      expect(conversation.reload.label_list).to be_empty
    end

    it 'marks a target that passed while the policy was there, though the check had not run yet' do
      travel_to(conversation.created_at + 2.hours + 10.seconds) { standard.destroy! }

      timer = timer_of(conversation)
      expect(timer.first_response_missed_at).to be_within(1.second).of(timer.started_at + 2.hours)
      expect(timer.stopped_at).to be_present
      expect(conversation.reload.label_list).to eq([Inclamo::Sla::LABEL])
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])

      described_class.check_due!(conversation.created_at + 3.days)
      expect(timer.reload.resolution_missed_at).to be_nil
      expect(notes(conversation).size).to eq(1)
    end

    it 'keeps what a timer already reached' do
      answer = reply(conversation)
      described_class.replied!(answer)

      standard.destroy!

      expect(timer_of(conversation).first_response_at).to be_within(1.second).of(answer.created_at)
    end

    it 'leaves timers that have nothing running as they are' do
      described_class.replied!(reply(conversation))
      described_class.resolved!(conversation, Time.current)

      standard.destroy!

      expect(timer_of(conversation).stopped_at).to be_nil
    end
  end
end
