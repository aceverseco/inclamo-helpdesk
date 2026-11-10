# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::Ai::Connect do
  include AiServiceStubs

  let(:account) { create(:account, name: 'Example Shop') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:other_website) { create(:inbox, account: account, name: 'Second site') }

  before { resolve_ai_service_publicly }

  def connect(inboxes = [website], code: ai_code)
    described_class.call(account: account, user: admin, code: code, inbox_ids: inboxes.map(&:id))
  end

  def made_by_us
    {
      bots: AgentBot.where(account_id: account.id).count,
      tokens: AccessToken.where(owner_type: 'AgentBot').count,
      inboxes: account.inboxes.count,
      labels: account.labels.count,
      links: AgentBotInbox.count,
      records: Inclamo::AiConnection.count
    }
  end

  context 'when the AI service accepts' do
    let!(:registration) { stub_ai_registration }

    it 'attaches the bot to the chosen inboxes only and points it at the address it was given' do
      record = connect

      bot = AgentBot.find(record.agent_bot_id)
      expect(bot).to have_attributes(account_id: account.id, outgoing_url: 'https://ai.example.com/webhooks/conn-1', name: 'AI agent')
      expect(website.reload.agent_bot).to eq(bot)
      expect(other_website.reload.agent_bot).to be_nil
      expect(record).to have_attributes(state: 'connected', connection_id: 'conn-1', inbox_ids: [website.id], connected_by: admin,
                                        service_url: 'https://ai.example.com')
    end

    it 'registers the account, the bot credentials, the Phone inbox and the inboxes' do
      record = connect([website, other_website])

      bot = AgentBot.find(record.agent_bot_id)
      phone = Inbox.find(record.phone_inbox_id)
      expect(phone).to have_attributes(name: 'Phone', channel_type: 'Channel::Api', account_id: account.id)
      expect(phone.agent_bot).to be_nil
      expected = {
        contract: 1, helpdesk_url: ENV.fetch('FRONTEND_URL', ''), account: { id: account.id, name: 'Example Shop' },
        bot: { id: bot.id, access_token: bot.access_token.token, secret: bot.secret },
        phone_inbox_id: phone.id, inbox_ids: [website.id, other_website.id]
      }
      expect(registration.with(body: expected.to_json)).to have_been_requested
    end

    it 'turns off keeping conversations pending when the bot fails' do
      account.update!(keep_pending_on_bot_failure: true)

      connect

      expect(account.reload.keep_pending_on_bot_failure).to be(false)
    end

    it 'creates the labels of the AI service with their meanings, leaving a label of the same title as it was' do
      existing = create(:label, account: account, title: 'inclamo_handover', description: 'Ours', color: '#000000')

      connect

      labels = account.labels.reload.index_by(&:title)
      expect(labels.keys).to include(*Inclamo::Ai::LABELS.keys)
      expect(labels['inclamo_urgent'].description).to eq(Inclamo::Ai::LABELS['inclamo_urgent'])
      expect(labels['inclamo_handover']).to have_attributes(id: existing.id, description: 'Ours', color: '#000000')
    end

    it 'reuses the Phone inbox of an earlier connection' do
      first = connect
      Inclamo::AiConnection.find(first.id).update!(state: 'disconnected')
      Inclamo::Ai.remove_bot(AgentBot.find(first.agent_bot_id))

      second = connect

      expect(second.id).to eq(first.id)
      expect(second.phone_inbox_id).to eq(first.phone_inbox_id)
      expect(account.inboxes.where(name: 'Phone').count).to eq(1)
    end

    it 'refuses an account that is connected already, without asking the AI service' do
      connect
      WebMock.reset_executed_requests!

      expect { connect([other_website]) }.to raise_error(Inclamo::Ai::Error::AlreadyConnected)
      expect(registration).not_to have_been_requested
    end

    it 'leaves nothing behind when the helpdesk cannot finish, and tells the AI service' do
      removal = stub_ai_removal
      allow(Inclamo::Ai::Labels).to receive(:ensure_fixed!).and_raise(ActiveRecord::RecordInvalid)
      before = made_by_us

      expect { connect }.to raise_error(ActiveRecord::RecordInvalid)
      expect(made_by_us).to eq(before)
      expect(removal).to have_been_requested
    end
  end

  context 'when the AI service refuses or does not answer' do
    it 'leaves no bot, no token, no new Phone inbox and no labels after a refusal' do
      stub_ai_registration(status: 410, body: { error: 'expired', message: 'This connection code has expired.' })
      before = made_by_us

      expect { connect }.to raise_error(Inclamo::Ai::Error::Refused, 'This connection code has expired.')
      expect(made_by_us).to eq(before)
      expect(account.reload.keep_pending_on_bot_failure).to be_falsy
    end

    it 'leaves nothing behind after a timeout' do
      stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_timeout
      before = made_by_us

      expect { connect }.to raise_error(Inclamo::Ai::Error::NotAnswered)
      expect(made_by_us).to eq(before)
    end

    it 'keeps the Phone inbox of an earlier connection after a refusal' do
      phone = create(:channel_api, account: account, webhook_url: nil).inbox
      create(:inclamo_ai_connection, account: account, state: 'disconnected', phone_inbox_id: phone.id)
      stub_ai_registration(status: 400, body: { error: 'invalid', message: 'No.' })

      expect { connect }.to raise_error(Inclamo::Ai::Error::Refused)
      expect(Inbox.exists?(phone.id)).to be(true)
    end
  end

  context 'before any request' do
    let!(:registration) { stub_ai_registration }

    it 'refuses text that is not a code' do
      expect { connect(code: 'not-a-code') }.to raise_error(Inclamo::Ai::Error::InvalidCode)
      expect(registration).not_to have_been_requested
      expect(AgentBot.count).to eq(0)
    end

    it 'refuses without an inbox, with an inbox of another account, and with the Phone inbox' do
      phone = create(:channel_api, account: account, webhook_url: nil).inbox
      create(:inclamo_ai_connection, account: account, state: 'disconnected', phone_inbox_id: phone.id)

      expect { connect([]) }.to raise_error(Inclamo::Ai::Error::NoInboxes)
      expect { connect([create(:inbox)]) }.to raise_error(Inclamo::Ai::Error::InvalidInbox)
      expect { connect([phone]) }.to raise_error(Inclamo::Ai::Error::InvalidInbox)
      expect(registration).not_to have_been_requested
    end

    it 'refuses an inbox that has another bot' do
      create(:agent_bot_inbox, inbox: other_website, agent_bot: create(:agent_bot, account: account))

      expect { connect([website, other_website]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
      expect(registration).not_to have_been_requested
      expect(website.reload.agent_bot).to be_nil
    end

    it 'refuses an inbox with a Dialogflow integration' do
      create(:integrations_hook, :dialogflow, account: account, inbox: other_website)

      expect { connect([other_website]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
      expect(registration).not_to have_been_requested
    end

    it 'refuses on an installation without encryption keys' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      expect { connect }.to raise_error(Inclamo::Ai::Error::EncryptionNotConfigured)
      expect(registration).not_to have_been_requested
    end
  end
end
