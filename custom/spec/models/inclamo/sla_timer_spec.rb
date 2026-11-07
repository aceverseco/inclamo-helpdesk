# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::SlaTimer do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def policy(**attributes)
    Inclamo::SlaPolicy.create!({ account: account, name: 'Standard', first_response_seconds: 7200, resolution_seconds: 172_800 }.merge(attributes))
  end

  it 'copies the targets of the policy when it is applied, so editing the policy does not move them' do
    standard = policy(business_hours_only: true)
    conversation = create(:conversation, account: account, inbox: inbox)
    timer = Inclamo::Sla::Timers.apply!(conversation)

    standard.update!(name: 'Renamed', first_response_seconds: 60, resolution_seconds: nil, business_hours_only: false)

    expect(timer.reload).to have_attributes(policy_id: standard.id, policy_name: 'Standard', first_response_seconds: 7200,
                                            resolution_seconds: 172_800, business_hours_only: true)
  end

  it 'is one per conversation' do
    policy
    conversation = create(:conversation, account: account, inbox: inbox)
    Inclamo::Sla::Timers.apply!(conversation)
    Inclamo::Sla::Timers.apply!(conversation)

    expect(described_class.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'goes with its conversation' do
    policy
    conversation = create(:conversation, account: account, inbox: inbox)
    Inclamo::Sla::Timers.apply!(conversation)

    conversation.destroy!

    expect(described_class.count).to eq(0)
  end

  it 'gives the deadline of each target from the start, and none for a target the policy does not set' do
    policy(resolution_seconds: nil)
    conversation = create(:conversation, account: account, inbox: inbox)
    timer = Inclamo::Sla::Timers.apply!(conversation)

    expect(timer.deadline('first_response')).to be_within(1.second).of(timer.started_at + 2.hours)
    expect(timer.deadline('resolution')).to be_nil
  end
end
