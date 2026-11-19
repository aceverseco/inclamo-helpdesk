# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# One connection service, two doors (capability app-agent-auto-connection,
# design D2, D4, D5): the "AI agent" page with a pasted code, a person and a
# chosen inbox, and the store app with the code's two fields, no person and
# the helpdesk's own choice of inboxes, which may be none.
RSpec.describe Inclamo::Ai::Connect, 'through both doors' do
  include AiServiceStubs

  let(:account) { create(:account, name: 'Example Shop') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let(:token) { 'one-time-token-for-specs' }
  let(:pairing) { Inclamo::Ai::Pairing.new(service_url: "#{AiServiceStubs::AI_SERVICE_URL}/", token: token) }

  before { resolve_ai_service_publicly }

  def through_page(inboxes = [website])
    described_class.call(account: account, user: admin, code: ai_code(token: token), inbox_ids: inboxes.map(&:id))
  end

  def through_app(inboxes = [website])
    described_class.call(account: account, user: nil, pairing: pairing, inbox_ids: -> { inboxes.map(&:id) }, allow_no_inboxes: true, via: 'app')
  end

  def registration_body(bot, phone, inbox_ids)
    {
      contract: 1, helpdesk_url: ENV.fetch('FRONTEND_URL', ''), account: { id: account.id, name: 'Example Shop' },
      bot: { id: bot.id, access_token: bot.access_token.token, secret: bot.secret },
      phone_inbox_id: phone.id, inbox_ids: inbox_ids
    }.to_json
  end

  def made_by_us
    {
      bots: AgentBot.where(account_id: account.id).count,
      tokens: AccessToken.where(owner_type: 'AgentBot').count,
      inboxes: account.inboxes.count,
      labels: account.labels.count,
      links: AgentBotInbox.count,
      active: Inclamo::AiConnection.active.count
    }
  end

  describe 'the second way of being given the address and the token' do
    it 'reads the pairing like a code: the address without a trailing slash and its registration address' do
      expect(pairing).to have_attributes(service_url: AiServiceStubs::AI_SERVICE_URL, token: token, connections_url: "#{AiServiceStubs::AI_SERVICE_URL}/connections")
      expect(pairing.inspect).not_to include(token)
      expect(pairing.to_s).not_to include(token)
    end

    { 'a pasted code' => :through_page, "the store app's pairing" => :through_app }.each do |door, connect|
      it "registers with the same call from #{door}" do
        registration = stub_ai_registration

        record = send(connect)

        bot = AgentBot.find(record.agent_bot_id)
        phone = Inbox.find(record.phone_inbox_id)
        expect(registration.with(body: registration_body(bot, phone, [website.id]), headers: { 'Authorization' => "Bearer #{token}" }))
          .to have_been_requested.once
        expect(record).to have_attributes(state: 'connected', service_url: AiServiceStubs::AI_SERVICE_URL, inbox_ids: [website.id])
        expect(website.reload.agent_bot).to eq(bot)
      end
    end

    it "keeps the page's door as it was: a code that does not read stops before any request" do
      registration = stub_ai_registration

      expect do
        described_class.call(account: account, user: admin, code: 'not-a-code', inbox_ids: [website.id])
      end.to raise_error(Inclamo::Ai::Error::InvalidCode)
      expect(registration).not_to have_been_requested
    end
  end

  describe 'a connection without inboxes' do
    let!(:registration) { stub_ai_registration }

    it 'stays refused on the page, where it is not allowed' do
      expect { through_page([]) }.to raise_error(Inclamo::Ai::Error::NoInboxes)
      expect do
        described_class.call(account: account, user: admin, code: ai_code(token: token), inbox_ids: -> { [] })
      end.to raise_error(Inclamo::Ai::Error::NoInboxes)
      expect(registration).not_to have_been_requested
      expect(AgentBot.where(account_id: account.id)).to be_empty
    end

    it 'connects for calls only when allowed: the bot, Phone and the labels exist, an empty list is registered, no inbox has the bot' do
      record = through_app([])

      bot = AgentBot.find(record.agent_bot_id)
      phone = Inbox.find(record.phone_inbox_id)
      expect(phone).to have_attributes(name: 'Phone', channel_type: 'Channel::Api')
      expect(account.labels.pluck(:title)).to include(*Inclamo::Ai::LABELS.keys)
      expect(registration.with(body: registration_body(bot, phone, []))).to have_been_requested.once
      expect(AgentBotInbox.where(agent_bot_id: bot.id)).to be_empty
      expect(account.inboxes.reload.map(&:agent_bot).compact).to be_empty
      expect(record).to have_attributes(state: 'connected', inbox_ids: [])
      expect(create(:conversation, account: account, inbox: website.reload).status).to eq('open')
    end

    it 'reads the choice under the account lock, once' do
      reads = 0
      chooser = lambda do
        reads += 1
        expect(Redis::Alfred.get("inclamo:ai:#{account.id}:connection")).to be_present
        [website.id]
      end

      described_class.call(account: account, user: nil, pairing: pairing, inbox_ids: chooser, allow_no_inboxes: true, via: 'app')

      expect(reads).to eq(1)
      expect(website.reload.agent_bot).to be_present
    end
  end

  describe 'without a person' do
    before { stub_ai_registration }

    it 'records no person and the app as the door' do
      record = through_app

      expect(record.reload).to have_attributes(connected_by: nil, connected_via: 'app')
    end

    it 'records the person and the page as the door on the page' do
      record = through_page

      expect(record.reload).to have_attributes(connected_by: admin, connected_via: 'page')
    end

    it 'records the door of the last connection when a disconnected one is reused' do
      first = through_app
      Inclamo::Ai.remove_bot(AgentBot.find(first.agent_bot_id))
      first.update!(state: 'disconnected')

      second = through_page

      expect(second.id).to eq(first.id)
      expect(second.reload).to have_attributes(connected_via: 'page', connected_by: admin)
    end
  end

  # Design D3 step 5 and task 2.5: every refusal, through either door, leaves
  # no bot, no token, no new Phone inbox, no labels and no connection.
  describe 'a refusal leaves nothing behind' do
    refusals = {
      'the AI service refuses' => lambda { |spec|
        spec.stub_ai_registration(status: 410, body: { error: 'invalid_token', message: 'This pairing token has expired.' })
        Inclamo::Ai::Error::Refused
      },
      'the AI service does not answer' => lambda { |spec|
        spec.stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_timeout
        Inclamo::Ai::Error::NotAnswered
      },
      'the AI service answers 201 without an address' => lambda { |spec|
        spec.stub_ai_registration(body: { connection_id: 'conn-1' })
        spec.stub_ai_removal
        Inclamo::Ai::Error::NotAnswered
      }
    }

    { 'the page' => :through_page, 'the store app' => :through_app }.each do |door, connect|
      refusals.each do |name, arrange|
        it "when #{name}, through #{door}" do
          error = arrange.call(self)
          before = made_by_us

          expect { send(connect) }.to raise_error(error)

          expect(made_by_us).to eq(before)
          expect(account.inboxes.where(name: 'Phone')).to be_empty
          expect(website.reload.agent_bot).to be_nil
        end
      end
    end

    it 'tells the AI service to forget a connection it made with an answer the helpdesk cannot use' do
      stub_ai_registration(body: { connection_id: 'conn-1' })
      removal = stub_ai_removal

      expect { through_app }.to raise_error(Inclamo::Ai::Error::NotAnswered)
      expect(removal).to have_been_requested
    end
  end

  # The app waits 15 seconds for its answer, the AI service is waited for at
  # most 10 of them; telling it to forget a connection gets what is left.
  describe 'within the time budget' do
    # An AI service that answers its registration after `takes` seconds of a
    # clock the spec moves, with a connection the helpdesk cannot use.
    let(:clock) { Struct.new(:now) { def call = now }.new(100.0) }
    let(:removals) { [] }

    def slow_client(takes:, removal_fails: false)
      spec_clock = clock
      seen = removals
      Class.new do
        define_method(:register) do |_code, _body|
          spec_clock.now += takes
          raise Inclamo::Ai::Error::NotAnswered.new('the AI service answered 201 without a webhook address', connection_id: 'conn-late')
        end
        define_method(:remove) do |**options|
          seen << options
          raise Inclamo::Ai::Error::NotAnswered, 'the AI service did not answer: Timeout::Error' if removal_fails

          true
        end
      end.new
    end

    def connect_within(budget, client)
      described_class.call(account: account, user: nil, pairing: pairing, inbox_ids: -> { [website.id] }, allow_no_inboxes: true, via: 'app',
                           time_budget: budget, client: client, clock: clock)
    end

    it 'gives the call to forget what is left of the budget, so the whole answer stays within it' do
      expect { connect_within(15, slow_client(takes: 10.5)) }.to raise_error(Inclamo::Ai::Error::NotAnswered)

      expect(removals.map { |options| options.slice(:connection_id, :time_limit) }).to eq([{ connection_id: 'conn-late', time_limit: 3.5 }])
      expect(10.5 + removals.first[:time_limit]).to be <= 15
    end

    it 'gives it a couple of seconds at least, and never more than the AI service is ever waited for' do
      connect_within(15, slow_client(takes: 13.5)) rescue nil # rubocop:disable Style/RescueModifier
      connect_within(15, slow_client(takes: 0.5)) rescue nil # rubocop:disable Style/RescueModifier

      expect(removals.pluck(:time_limit)).to eq([Inclamo::Ai::Connect::FORGET_MINIMUM, Inclamo::Ai::TIME_LIMIT])
    end

    it 'does not wait on a call to forget that fails: the connection is answered as not answered, and the log names it' do
      allow(Rails.logger).to receive(:warn)

      expect { connect_within(15, slow_client(takes: 10, removal_fails: true)) }.to raise_error(Inclamo::Ai::Error::NotAnswered, /without a webhook address/)

      expect(removals.size).to eq(1)
      expect(Rails.logger).to have_received(:warn).with(/could not be told to forget connection conn-late: Inclamo::Ai::Error::NotAnswered/)
      expect(made_by_us[:bots]).to eq(0)
    end

    it 'leaves the page without a budget: forgetting waits as long as any call to the AI service' do
      expect do
        described_class.call(account: account, user: admin, code: ai_code(token: token), inbox_ids: [website.id],
                             client: slow_client(takes: 12), clock: clock)
      end.to raise_error(Inclamo::Ai::Error::NotAnswered)

      expect(removals.pluck(:time_limit)).to eq([Inclamo::Ai::TIME_LIMIT])
    end
  end
end

RSpec.describe Inclamo::Ai::ServiceClient, 'removal within a time limit' do
  include AiServiceStubs

  before { resolve_ai_service_publicly }

  before { allow(Timeout).to receive(:timeout).and_call_original }

  it 'waits at most the time it is given' do
    stub_ai_removal

    described_class.new.remove(service_url: AiServiceStubs::AI_SERVICE_URL, connection_id: 'conn-1', token: 'bot-token', time_limit: 3.5)

    expect(Timeout).to have_received(:timeout).with(3.5)
    expect(Timeout).not_to have_received(:timeout).with(Inclamo::Ai::TIME_LIMIT)
  end

  it 'waits the usual time when it is given none' do
    stub_ai_removal

    described_class.new.remove(service_url: AiServiceStubs::AI_SERVICE_URL, connection_id: 'conn-1', token: 'bot-token')

    expect(Timeout).to have_received(:timeout).with(Inclamo::Ai::TIME_LIMIT)
  end
end
