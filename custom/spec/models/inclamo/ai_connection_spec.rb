# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::AiConnection do
  it 'allows one connection per account' do
    first = create(:inclamo_ai_connection)
    second = build(:inclamo_ai_connection, account: first.account)

    expect(second).not_to be_valid
    expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'knows the three states, and that a disconnected one is not active' do
    expect(described_class.states.keys).to eq(%w[connected failing disconnected])
    expect(build(:inclamo_ai_connection, state: 'failing')).to be_active
    expect(build(:inclamo_ai_connection, state: 'disconnected')).not_to be_active
  end

  it 'is refused on an installation without encryption keys, but can still be marked disconnected' do
    record = create(:inclamo_ai_connection)
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

    expect(build(:inclamo_ai_connection)).not_to be_valid
    expect(build(:inclamo_ai_connection).tap(&:valid?).errors[:base].join).to include('encryption')
    expect(record.update(state: 'disconnected')).to be(true)
  end

  # agent-inbox-selection, design D7: the inboxes the agent answers in are the
  # chosen ones that still carry the connection's bot.
  describe 'the inboxes the agent answers in' do
    let(:account) { create(:account) }
    let(:bot) { create(:agent_bot, account: account) }
    let!(:website) { create(:inbox, account: account, name: 'Website') }
    let!(:email) { create(:inbox, account: account, name: 'Email') }
    let!(:chat) { create(:inbox, account: account, name: 'Chat') }
    let(:record) do
      [website, email].each { |inbox| create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }
      create(:inclamo_ai_connection, account: account, agent_bot: bot, inbox_ids: [email.id, website.id])
    end

    def fresh
      described_class.find(record.id)
    end

    def queries_of(table)
      count = 0
      counter = ->(*, payload) { count += 1 if payload[:sql].include?(table) }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
      count
    end

    it 'covers only the chosen inboxes that carry its bot, in the chosen order, and none once disconnected' do
      expect(record.answering_inbox_ids).to eq([email.id, website.id])
      expect(record.covers?(website.id)).to be(true)
      expect(record.covers?(email.id.to_s)).to be(true)
      expect(record.covers?(chat.id)).to be(false)
      record.update!(state: 'disconnected')
      expect(record.covers?(website.id)).to be(false)
      expect(record.answering_inbox_ids).to eq([])
    end

    it 'stops counting an inbox the team deleted at once, before Chatwoot removes its bot link' do
      record
      email.destroy!

      expect(AgentBotInbox.where(agent_bot_id: bot.id, inbox_id: email.id)).to exist
      expect(fresh.answering_inbox_ids).to eq([website.id])
      expect(fresh.covers?(email.id)).to be(false)
      expect(fresh.connected_inbox_ids).to eq([email.id, website.id])
    end

    it "stops counting an inbox whose bot was changed or removed in Chatwoot's own inbox settings" do
      record
      email.agent_bot_inbox.update!(agent_bot: create(:agent_bot, account: account))
      website.agent_bot_inbox.destroy!

      expect(fresh.answering_inbox_ids).to eq([])
      expect(fresh.covers?(email.id)).to be(false)
      expect(fresh.covers?(website.id)).to be(false)
    end

    it 'does not start counting an inbox given its bot behind the page' do
      record
      create(:agent_bot_inbox, inbox: chat, agent_bot: bot)

      expect(fresh.covers?(chat.id)).to be(false)
      expect(fresh.answering_inbox_ids).to eq([email.id, website.id])
    end

    it 'asks the database once per record, and again after a reload or a save' do
      connection = fresh

      expect(queries_of('agent_bot_inboxes') { 3.times { connection.covers?(website.id) } }).to eq(1)
      expect(queries_of('agent_bot_inboxes') { connection.reload.covers?(website.id) }).to eq(1)
      connection.update!(inbox_ids: [website.id])
      expect(queries_of('agent_bot_inboxes') { expect(connection.covers?(email.id)).to be(false) }).to eq(1)
    end

    it 'asks nothing for a connection with no inbox' do
      connection = create(:inclamo_ai_connection, account: create(:account), agent_bot: create(:agent_bot), inbox_ids: [])

      expect(queries_of('agent_bot_inboxes') { connection.covers?(website.id) }).to eq(0)
    end
  end

  describe 'why the last change of the inboxes was not completed' do
    it 'reads nothing for a connection made before the column, and keeps the three reasons only' do
      record = create(:inclamo_ai_connection)
      expect(record.reload.inbox_change_error).to be_nil
      expect(described_class.columns_hash['inbox_change_error']).to have_attributes(null: true, default: nil)

      %w[not_applied not_applied_service_not_told storefront_not_added].each do |reason|
        expect(record.update(inbox_change_error: reason)).to be(true)
      end
      expect(record.update(inbox_change_error: 'something_else')).to be(false)
    end
  end

  describe 'the door a connection came through' do
    it 'reads as made on the page unless it says otherwise, as every connection made before the column' do
      expect(create(:inclamo_ai_connection).reload.connected_via).to eq('page')
      expect(described_class.columns_hash['connected_via']).to have_attributes(default: 'page', null: false)
    end

    it 'knows the page and the store app, and nothing else' do
      expect(build(:inclamo_ai_connection, connected_via: 'app')).to be_valid
      expect(build(:inclamo_ai_connection, connected_via: 'elsewhere')).not_to be_valid
      record = create(:inclamo_ai_connection)
      expect { record.update_column(:connected_via, 'elsewhere') }.to raise_error(ActiveRecord::StatementInvalid) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'needs no person for a connection the app made' do
      expect(create(:inclamo_ai_connection, connected_via: 'app', connected_by: nil)).to be_persisted
    end
  end

  describe 'delivery health' do
    let(:record) { create(:inclamo_ai_connection) }

    it 'turns failing on a failure and connected on the next delivery' do
      described_class.record_failure(record.id, 'http_503')
      expect(record.reload).to have_attributes(state: 'failing', last_error: 'http_503', last_failed_at: be_present)

      described_class.record_delivery(record.id)
      expect(record.reload).to have_attributes(state: 'connected', last_delivered_at: be_present, last_error: 'http_503')
    end

    it 'never brings a disconnected connection back' do
      record.update!(state: 'disconnected')

      described_class.record_delivery(record.id)
      described_class.record_failure(record.id, 'timeout')

      expect(record.reload).to have_attributes(state: 'disconnected', last_delivered_at: nil, last_failed_at: nil)
    end
  end
end
