# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# Capability agent-inbox-selection: an administrator changes the inboxes of a
# live connection (design D2, D3, D5; docs/ai-connector.md §1.4).
RSpec.describe Inclamo::Ai::ChangeInboxes do
  include AiServiceStubs

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:person) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:email) { create(:inbox, account: account, name: 'Email') }
  let!(:chat) { create(:inbox, account: account, name: 'Chat') }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:told) { [] }

  before { resolve_ai_service_publicly }

  def change(inboxes, user: admin)
    described_class.call(account: account, user: user, inbox_ids: inboxes.map { |inbox| inbox.is_a?(Inbox) ? inbox.id : inbox })
  end

  def links
    AgentBotInbox.where(agent_bot_id: bot.id).order(:inbox_id).pluck(:inbox_id)
  end

  # What a change must leave untouched when it does not happen.
  def state_of_everything
    {
      links: AgentBotInbox.order(:id).pluck(:inbox_id, :agent_bot_id, :status),
      column: record.reload.inbox_ids,
      conversations: Conversation.where(account_id: account.id).order(:id).pluck(:id, :status, :assignee_id, :assignee_agent_bot_id),
      error: record.inbox_change_error
    }
  end

  describe 'a change the AI service accepts' do
    before { stub_ai_inbox_change(told: told) }

    it 'adds an inbox: attaches the bot, writes the list and tells the AI service the whole list' do
      token = bot.access_token.token
      connected_at = record.connected_at

      change([website, email])

      expect(told).to eq([[website.id, email.id]])
      expect(links).to eq([website.id, email.id])
      expect(email.reload.agent_bot).to eq(bot)
      expect(record.reload).to have_attributes(inbox_ids: [website.id, email.id], state: 'connected', agent_bot_id: bot.id, connected_at: connected_at,
                                               inbox_change_error: nil)
      expect(bot.reload.access_token.token).to eq(token)
      expect(Inbox.exists?(record.phone_inbox_id)).to be(true)
      expect(create(:conversation, account: account, inbox: email.reload)).to have_attributes(status: 'pending', assignee_agent_bot_id: bot.id)
    end

    it "removes an inbox: detaches the bot and hands only that inbox's pending conversations to the team" do
      record.update!(inbox_ids: [website.id, email.id])
      create(:agent_bot_inbox, inbox: email, agent_bot: bot)
      first = create(:conversation, account: account, inbox: website)
      second = create(:conversation, account: account, inbox: website)
      kept = create(:conversation, account: account, inbox: email.reload)
      open_one = create(:conversation, account: account, inbox: website, status: :open, assignee: person)

      change([email])

      expect([first, second].map { |conversation| conversation.reload.slice(:status, :assignee_agent_bot_id).values }).to eq([['open', nil], ['open', nil]])
      expect(kept.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: bot.id)
      expect(open_one.reload).to have_attributes(status: 'open', assignee_id: person.id)
      expect(links).to eq([email.id])
      expect(record.reload.inbox_ids).to eq([email.id])
      expect(create(:conversation, account: account, inbox: website.reload).status).to eq('open')
    end

    it 'adds and removes in one change and one call' do
      pending_one = create(:conversation, account: account, inbox: website)

      change([email, chat])

      expect(told).to eq([[email.id, chat.id]])
      expect(links).to eq([email.id, chat.id])
      expect(pending_one.reload.status).to eq('open')
      expect(record.reload.inbox_ids).to eq([email.id, chat.id])
    end

    it 'leaves the conversations that already exist in an added inbox with the team' do
      open_one = create(:conversation, account: account, inbox: email, status: :open, assignee: person)

      change([website, email])

      expect(open_one.reload).to have_attributes(status: 'open', assignee_id: person.id, assignee_agent_bot_id: nil)
    end

    it 'calls nobody and changes nothing for the list the agent already has, in any order' do
      record.update!(inbox_ids: [website.id, email.id])
      create(:agent_bot_inbox, inbox: email, agent_bot: bot)
      before = state_of_everything
      updated_at = record.reload.updated_at

      change([email, website, email])

      expect(told).to eq([])
      expect(state_of_everything).to eq(before)
      expect(record.reload.updated_at).to eq(updated_at)
    end

    it 'leaves the connection on for calls only with an empty list, the Phone inbox and the bot intact' do
      pending_one = create(:conversation, account: account, inbox: website)

      change([])

      expect(told).to eq([[]])
      expect(record.reload).to have_attributes(state: 'connected', inbox_ids: [])
      expect(links).to eq([])
      expect(AgentBot.exists?(bot.id)).to be(true)
      expect(Inbox.find(record.phone_inbox_id).name).to eq('Phone')
      expect(pending_one.reload.status).to eq('open')
      expect(create(:conversation, account: account, inbox: website.reload).status).to eq('open')

      change([website])

      expect(links).to eq([website.id])
    end

    it 'drops a deleted inbox from the list it writes, and does not tell it as removed' do
      record.update!(inbox_ids: [website.id, email.id])
      create(:agent_bot_inbox, inbox: email, agent_bot: bot)
      email.destroy!

      change([website, chat])

      expect(told).to eq([[website.id, chat.id]])
      expect(record.reload.inbox_ids).to eq([website.id, chat.id])
    end

    it "takes an inbox that already carries the agent's bot without a second link" do
      create(:agent_bot_inbox, inbox: chat, agent_bot: bot)

      change([website, chat])

      expect(AgentBotInbox.where(inbox_id: chat.id).count).to eq(1)
      expect(record.reload.inbox_ids).to eq([website.id, chat.id])
    end

    it 'clears the reason the last change was not completed' do
      record.update!(inbox_change_error: 'not_applied')

      change([website, email])

      expect(record.reload.inbox_change_error).to be_nil
    end
  end

  describe 'a change that names an inbox the agent cannot take' do
    let!(:stub) { stub_ai_inbox_change(told: told) }

    it 'refuses it whole before asking the AI service, and changes nothing' do
      elsewhere = create(:inbox)
      create(:agent_bot_inbox, inbox: email, agent_bot: create(:agent_bot, account: account))
      flow = create(:inbox, account: account)
      build(:integrations_hook, :dialogflow, account: account, inbox: flow).save!(validate: false)
      create(:conversation, account: account, inbox: website)
      before = state_of_everything

      expect { change([website, chat, elsewhere]) }.to raise_error(Inclamo::Ai::Error::InvalidInbox)
      expect { change([chat, record.phone_inbox_id]) }.to raise_error(Inclamo::Ai::Error::InvalidInbox)
      expect { change([website, chat, email]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
      expect { change([chat, flow]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)

      expect(stub).not_to have_been_requested
      expect(state_of_everything).to eq(before)
    end

    it 'refuses an account that is not connected and makes nothing' do
      record.update!(state: 'disconnected')

      expect { change([website]) }.to raise_error(Inclamo::Ai::Error::NotConnected)
      expect(stub).not_to have_been_requested
    end
  end

  describe 'a change the AI service does not accept' do
    {
      'refuses' => [{ status: 422, body: { error: 'plan_limit', message: 'One inbox on this plan.' } }, Inclamo::Ai::Error::Refused],
      'does not know the call' => [{ status: 404, body: '' }, Inclamo::Ai::Error::ChangeUnsupported],
      'does not answer' => [{ status: 503, body: '' }, Inclamo::Ai::Error::NotAnswered]
    }.each do |what, (answer, error)|
      it "changes nothing when the AI service #{what}" do
        stub_ai_inbox_change(**answer, told: told)
        create(:conversation, account: account, inbox: website)
        create(:conversation, account: account, inbox: website, status: :open, assignee: person)
        before = state_of_everything

        expect { change([email]) }.to raise_error(error)

        expect(told).to eq([[email.id]])
        expect(state_of_everything).to eq(before)
      end
    end

    it 'changes nothing when the AI service is silent past the time limit' do
      stub_request(:put, "#{AiServiceStubs::AI_SERVICE_URL}/connections/conn-1/inboxes").to_timeout
      before = state_of_everything

      expect { change([email]) }.to raise_error(Inclamo::Ai::Error::NotAnswered)
      expect(state_of_everything).to eq(before)
    end
  end

  describe 'when the helpdesk cannot apply a list the AI service accepted' do
    def fail_in_the_transaction
      allow(AgentBotInbox).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    end

    it 'keeps the earlier inboxes, asks the AI service to take the earlier list back and says the change was not completed' do
      stub_ai_inbox_change(told: told)
      fail_in_the_transaction

      expect { change([email]) }.to raise_error(Inclamo::Ai::Error::NotApplied)

      expect(told).to eq([[email.id], [website.id]])
      expect(links).to eq([website.id])
      expect(record.reload).to have_attributes(inbox_ids: [website.id], inbox_change_error: 'not_applied', state: 'connected')
    end

    it 'says the AI service could not be told when taking back fails too' do
      stub_ai_inbox_change(status: [204, 503], told: told)
      fail_in_the_transaction

      expect { change([email]) }.to raise_error(Inclamo::Ai::Error::NotApplied)

      expect(told).to eq([[email.id], [website.id]])
      expect(record.reload.inbox_change_error).to eq('not_applied_service_not_told')
    end

    it 'leaves the conversations it handed over with the team, and a later change clears the reason' do
      stub_ai_inbox_change(told: told)
      handed = create(:conversation, account: account, inbox: website)
      allow_any_instance_of(Inclamo::AiConnection).to receive(:update!).and_raise(ActiveRecord::ActiveRecordError) # rubocop:disable RSpec/AnyInstance

      expect { change([email]) }.to raise_error(Inclamo::Ai::Error::NotApplied)

      expect(handed.reload.status).to eq('open')
      expect(links).to eq([website.id])
      expect(record.reload.inbox_change_error).to eq('not_applied')

      allow_any_instance_of(Inclamo::AiConnection).to receive(:update!).and_call_original # rubocop:disable RSpec/AnyInstance
      change([email])

      expect(record.reload).to have_attributes(inbox_ids: [email.id], inbox_change_error: nil)
    end
  end

  describe 'one change of the connection at a time' do
    it 'is refused as busy while another change, a connection or a disconnection holds the lock' do
      stub = stub_ai_inbox_change(told: told)

      Inclamo::Ai.with_account_lock(account) do
        expect { change([website, email]) }.to raise_error(Inclamo::Ai::Error::Busy)
      end
      expect(stub).not_to have_been_requested
      expect(record.reload.inbox_ids).to eq([website.id])
    end

    it 'keeps a disconnection out while the AI service is being told, and a change out of a disconnection' do
      during_change = nil
      stub_request(:put, "#{AiServiceStubs::AI_SERVICE_URL}/connections/conn-1/inboxes").to_return do
        during_change = begin
          Inclamo::Ai::Disconnect.call(account: account)
        rescue Inclamo::Ai::Error => e
          e
        end
        { status: 204 }
      end

      change([website, email])

      expect(during_change).to be_a(Inclamo::Ai::Error::Busy)
      expect(record.reload).to have_attributes(state: 'connected', inbox_ids: [website.id, email.id])

      during_disconnection = nil
      stub_request(:delete, "#{AiServiceStubs::AI_SERVICE_URL}/connections/conn-1").to_return do
        during_disconnection = begin
          change([website])
        rescue Inclamo::Ai::Error => e
          e
        end
        { status: 204 }
      end

      Inclamo::Ai::Disconnect.call(account: account)

      expect(during_disconnection).to be_a(Inclamo::Ai::Error::Busy)
      expect(record.reload.state).to eq('disconnected')
    end
  end
end
