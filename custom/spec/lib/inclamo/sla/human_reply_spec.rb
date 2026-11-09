# frozen_string_literal: true

require 'rails_helper'

# One message of each kind Chatwoot sends into a conversation; only a public
# reply by a person meets the first-response target.
RSpec.describe Inclamo::Sla::HumanReply do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }

  after { Current.reset }

  def outgoing(**attributes)
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :outgoing, sender: agent, **attributes)
  end

  it "counts an agent's public reply" do
    expect(described_class.match?(outgoing(content: 'Hello, I am looking into it'))).to be(true)
  end

  it 'counts the message of a macro an agent runs: it is sent as the agent' do
    sent = Messages::MessageBuilder.new(agent, conversation, { content: 'Macro text', private: false }).perform

    expect(described_class.match?(sent)).to be(true)
  end

  it 'counts a reply a person sent from the channel\'s own app' do
    expect(described_class.match?(outgoing(sender: nil, content_attributes: { external_echo: true }))).to be(true)
  end

  it 'does not count a private note' do
    expect(described_class.match?(outgoing(private: true))).to be(false)
  end

  it "does not count the customer's message" do
    expect(described_class.match?(create(:message, account: account, conversation: conversation, inbox: conversation.inbox,
                                                   message_type: :incoming, sender: conversation.contact))).to be(false)
  end

  it 'does not count a message an automation rule sends' do
    rule = create(:automation_rule, account: account, actions: [{ 'action_name' => 'send_message', 'action_params' => ['We got your message'] }])
    AutomationRules::ActionService.new(rule, account, conversation).perform

    sent = conversation.messages.outgoing.last
    expect(sent.content_attributes['automation_rule_id']).to eq(rule.id)
    expect(described_class.match?(sent)).to be(false)
  end

  it "does not count a bot's message" do
    bot = create(:agent_bot, account: account)

    expect(described_class.match?(outgoing(sender: bot))).to be(false)
  end

  it 'does not count a campaign message' do
    expect(described_class.match?(outgoing(additional_attributes: { campaign_id: 1 }))).to be(false)
  end

  it 'does not count a forwarded email' do
    expect(described_class.match?(outgoing(content_attributes: { forwarded_message_id: 1 }))).to be(false)
  end
end
