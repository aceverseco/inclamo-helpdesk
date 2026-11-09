# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::SlaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def event(name, **data)
    Events::Base.new(name, Time.zone.now, data)
  end

  it "is one of the listeners of Chatwoot's dispatcher" do
    expect(AsyncDispatcher.new.listeners).to include(listener)
  end

  it 'applies the timer, then reaches its targets, on the events of the conversation' do
    Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 7_200, resolution_seconds: 172_800)
    conversation = create(:conversation, account: account)

    listener.conversation_created(event('conversation.created', conversation: conversation))
    timer = Inclamo::SlaTimer.find_by(conversation_id: conversation.id)
    expect(timer).to be_present

    answer = create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :outgoing, sender: agent)
    listener.message_created(event('message.created', message: answer))
    resolved = event('conversation.resolved', conversation: conversation)
    listener.conversation_resolved(resolved)

    expect(timer.reload.first_response_at).to be_within(1.second).of(answer.created_at)
    expect(timer.resolved_at).to be_within(1.second).of(resolved.timestamp)
  end

  it 'never fails the event for the other listeners' do
    conversation = create(:conversation, account: account)
    allow(Inclamo::Sla::Timers).to receive(:apply!).and_raise(StandardError, 'unexpected')

    expect { listener.conversation_created(event('conversation.created', conversation: conversation)) }.not_to raise_error
  end
end
