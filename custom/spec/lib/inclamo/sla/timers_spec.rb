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
      expect(conversation.reload.label_list).to eq([Inclamo::Sla::LABEL])
      expect(notes(conversation)).to eq(['SLA "Standard": the first-response target of 2 hours was missed.'])
      expect(account.labels.find_by(title: Inclamo::Sla::LABEL)).to have_attributes(show_on_sidebar: true)
    end

    it 'marks a missed resolution when the conversation is still open, and keeps one label' do
      described_class.check_due!(conversation.created_at + 2.days + 1.minute)

      timer = timer_of(conversation)
      expect(timer.resolution_missed_at).to be_within(1.second).of(timer.started_at + 2.days)
      expect(conversation.reload.label_list).to eq([Inclamo::Sla::LABEL])
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
      expect(conversation.reload.label_list).to eq([Inclamo::Sla::LABEL])
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
