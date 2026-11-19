# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# PUT stores/{shop}/agent (design D2, D4, D6, D7; tasks 3.4, 3.5, 3.6).
RSpec.describe 'App agent connection: connecting', type: :request do
  include_context 'with the store app and the AI service'

  def answer
    response.parsed_body
  end

  let(:account) { provisioned.account }
  let(:storefront) { provisioned.storefront_inbox }

  before { provision }

  def registered_inbox_ids(registration)
    ids = nil
    expect(registration.with { |request| ids = JSON.parse(request.body)['inbox_ids'] }).to have_been_requested.once
    ids
  end

  describe 'a connection' do
    it 'answers as the contract says, with the storefront inbox and the Phone inbox' do
      registration = stub_ai_registration

      connect_agent

      record = connection_of(account)
      expect(response).to have_http_status(:created)
      expect(answer).to eq(
        'contract' => 1, 'state' => 'connected', 'outcome' => 'connected', 'inbox_ids' => [storefront.id],
        'phone_inbox_id' => record.phone_inbox_id, 'connected_at' => record.connected_at.utc.iso8601
      )
      expect(Inbox.find(record.phone_inbox_id)).to have_attributes(name: 'Phone', channel_type: 'Channel::Api', account_id: account.id)
      expect(registered_inbox_ids(registration)).to eq([storefront.id])
      expect(record).to have_attributes(connected_via: 'app', connected_by: nil, inbox_ids: [storefront.id], service_url: AiServiceStubs::AI_SERVICE_URL)
    end

    it 'registers with the bot and the address people open, the origin of the provisioning answer' do
      registration = stub_ai_registration
      helpdesk_url = ask_status.parsed_body['helpdesk_url']

      connect_agent

      sent = nil
      expect(registration.with { |request| sent = JSON.parse(request.body) }).to have_been_requested
      bot = AgentBot.find(connection_of(account).agent_bot_id)
      expect(URI.join(sent['helpdesk_url'], '/').to_s).to eq(URI.join(helpdesk_url, '/').to_s)
      expect(sent).to include('contract' => 1, 'account' => { 'id' => account.id, 'name' => account.name },
                              'bot' => { 'id' => bot.id, 'access_token' => bot.access_token.token, 'secret' => bot.secret })
      expect(registration.with(headers: { 'Authorization' => "Bearer #{AgentProvisioningRequests::PAIRING_TOKEN}" })).to have_been_requested
    end

    it 'never answers the bot token, its secret or the pairing token' do
      stub_ai_registration

      connect_agent

      bot = AgentBot.find(connection_of(account).agent_bot_id)
      [bot.access_token.token, bot.secret, AgentProvisioningRequests::PAIRING_TOKEN].each { |secret| expect(response.body).not_to include(secret) }
    end

    it 'holds a shopper\'s new message in the storefront inbox for the agent' do
      stub_ai_registration

      connect_agent

      conversation = create(:conversation, account: account, inbox: storefront.reload)
      expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: connection_of(account).agent_bot_id)
    end

    it 'attaches the bot to the storefront inbox only, whatever other inboxes the account has' do
      registration = stub_ai_registration
      email = create(:inbox, :with_email, account: account)
      second_site = create(:inbox, account: account, name: 'Second site')

      connect_agent

      expect(answer['inbox_ids']).to eq([storefront.id])
      expect(registered_inbox_ids(registration)).to eq([storefront.id])
      expect(storefront.reload.agent_bot).to be_present
      expect(email.reload.agent_bot).to be_nil
      expect(second_site.reload.agent_bot).to be_nil
      expect(create(:conversation, account: account, inbox: email).status).to eq('open')
    end

    it 'ignores inboxes named in the request' do
      registration = stub_ai_registration
      email = create(:inbox, :with_email, account: account)

      connect_agent(with: { inbox_ids: [email.id] })

      expect(response).to have_http_status(:created)
      expect(answer['inbox_ids']).to eq([storefront.id])
      expect(registered_inbox_ids(registration)).to eq([storefront.id])
      expect(email.reload.agent_bot).to be_nil
    end

    it 'leaves a storefront inbox that has another bot to that bot, and connects for calls only' do
      registration = stub_ai_registration
      other = create(:agent_bot, account: account, name: 'Other bot')
      create(:agent_bot_inbox, inbox: storefront, agent_bot: other)

      connect_agent

      expect(response).to have_http_status(:created)
      expect(answer['inbox_ids']).to eq([])
      expect(answer['phone_inbox_id']).to be_present
      expect(registered_inbox_ids(registration)).to eq([])
      expect(storefront.reload.agent_bot).to eq(other)
    end

    it 'connects an account without a storefront inbox for calls only' do
      registration = stub_ai_registration
      storefront.destroy!
      website = create(:inbox, account: account, name: 'Team site')

      connect_agent

      record = connection_of(account)
      expect(response).to have_http_status(:created)
      expect(answer).to include('outcome' => 'connected', 'inbox_ids' => [], 'phone_inbox_id' => record.phone_inbox_id)
      expect(registered_inbox_ids(registration)).to eq([])
      expect(AgentBotInbox.where(agent_bot_id: record.agent_bot_id)).to be_empty
      expect(create(:conversation, account: account, inbox: website.reload).status).to eq('open')
    end
  end

  describe 'asking again' do
    let!(:registration) { stub_ai_registration }

    before { connect_agent }

    it 'answers the same connection as existed, without a second registration' do
      record = connection_of(account)
      bot_id = record.agent_bot_id

      connect_agent(with: { token: 'another-token-that-must-not-be-used' })

      expect(response).to have_http_status(:ok)
      expect(answer).to eq(
        'contract' => 1, 'state' => 'connected', 'outcome' => 'existed', 'inbox_ids' => [storefront.id],
        'phone_inbox_id' => record.phone_inbox_id, 'connected_at' => record.connected_at.utc.iso8601
      )
      expect(registration).to have_been_requested.once
      expect(connection_of(account).agent_bot_id).to eq(bot_id)
      expect(agent_bots_of(account).count).to eq(1)
    end

    it 'answers the inboxes as they are now, and does not attach a storefront inbox made after the connection' do
      storefront.destroy!
      ask_for_chat
      new_storefront = storefront_inbox
      expect(new_storefront).to be_present

      connect_agent

      expect(answer).to include('outcome' => 'existed', 'inbox_ids' => [])
      expect(new_storefront.reload.agent_bot).to be_nil
      expect(create(:conversation, account: account, inbox: new_storefront).status).to eq('open')
      expect(registration).to have_been_requested.once
    end

    it 'answers a failing connection as it is' do
      Inclamo::AiConnection.record_failure(connection_of(account).id, 'http_503')

      connect_agent

      expect(response).to have_http_status(:ok)
      expect(answer).to include('state' => 'failing', 'outcome' => 'existed')
    end

    it 'refuses another allowed address as already connected, and changes nothing' do
      with_modified_env INCLAMO_APP_AGENT_SERVICE_URLS: "#{AiServiceStubs::AI_SERVICE_URL},https://other-ai.example.org" do
        other = stub_request(:post, 'https://other-ai.example.org/connections')
        before = made_for_agent(account)

        connect_agent(with: { service_url: 'https://other-ai.example.org' })

        expect(response).to have_http_status(:conflict)
        expect(answer).to eq('error' => 'agent_connected')
        expect(other).not_to have_been_requested
        expect(made_for_agent(account)).to eq(before)
        expect(connection_of(account).service_url).to eq(AiServiceStubs::AI_SERVICE_URL)
        expect(storefront.reload.agent_bot).to be_present
      end
    end
  end

  describe 'a connection made on the page' do
    it 'is answered as existed for the same address, and left as it is' do
      registration = stub_ai_registration
      administrator = User.from_email('alex@example.test')
      email = create(:inbox, :with_email, account: account)
      post "/api/v1/accounts/#{account.id}/inclamo/ai/connection",
           params: { connection_code: ai_code, inbox_ids: [email.id] }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      connect_agent

      expect(response).to have_http_status(:ok)
      expect(answer).to include('outcome' => 'existed', 'inbox_ids' => [email.id])
      expect(connection_of(account)).to have_attributes(connected_via: 'page', connected_by: administrator)
      expect(storefront.reload.agent_bot).to be_nil
      expect(registration).to have_been_requested.once
    end
  end

  describe 'while another connection or disconnection is under way' do
    it 'answers busy with the time to try again, and makes nothing' do
      registration = stub_ai_registration
      hold_connection_lock(account)

      expect { connect_agent }.not_to(change { made_for_agent(account) })

      expect(response).to have_http_status(:conflict)
      expect(answer).to eq('error' => 'busy')
      expect(response.headers['Retry-After']).to eq('5')
      expect(registration).not_to have_been_requested
    ensure
      release_connection_lock(account)
    end

    it 'refuses an account suspended between the first look and the lock, before anything is made' do
      registration = stub_ai_registration
      allow(Inclamo::AiConnection).to receive(:active_for).and_wrap_original do |original, *args|
        provisioned.update!(state: 'suspended')
        original.call(*args)
      end

      expect { connect_agent }.not_to(change { made_for_agent(account) })

      expect(response).to have_http_status(:conflict)
      expect(answer).to eq('error' => 'account_suspended')
      expect(registration).not_to have_been_requested
    end
  end

  describe "the AI service's answers" do
    # What a new account has before the agent is asked for: its own inboxes
    # and the labels of its ready queues, and no agent.
    let!(:before) { made_for_agent(account) }

    def expect_nothing_left
      expect(made_for_agent(account)).to eq(before)
      expect(agent_bots_of(account)).to be_empty
      expect(account.inboxes.where(name: 'Phone')).to be_empty
      expect(account.labels.where('title LIKE ?', 'inclamo\_%')).to be_empty
      expect(storefront.reload.agent_bot).to be_nil
      expect(Inclamo::AiConnection.active_for(account.id)).to be_nil
    end

    it "refuses with the AI service's own message and error, word for word" do
      stub_ai_registration(status: 410, body: { error: 'invalid_token', message: 'This pairing token has expired.' })

      connect_agent

      expect(response).to have_http_status(:unprocessable_entity)
      expect(answer).to eq('error' => 'agent_refused', 'message' => 'This pairing token has expired.', 'service_error' => 'invalid_token')
      expect_nothing_left
    end

    it 'passes on each error the AI service names' do
      %w[invalid_token wrong_helpdesk wrong_account already_connected store_inactive].each do |service_error|
        stub_ai_registration(status: 409, body: { error: service_error, message: "Refused: #{service_error}" })

        connect_agent

        expect(answer).to eq('error' => 'agent_refused', 'message' => "Refused: #{service_error}", 'service_error' => service_error)
      end
      expect_nothing_left
    end

    it 'says the AI service did not answer, after at most ten seconds of waiting' do
      stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_timeout

      connect_agent

      expect(response).to have_http_status(:bad_gateway)
      expect(answer).to eq('error' => 'agent_not_answered')
      expect(Inclamo::Ai::TIME_LIMIT).to eq(10)
      expect_nothing_left
    end

    it 'says the AI service did not answer when it answers 201 without an address' do
      stub_ai_registration(body: { connection_id: 'conn-1' })
      removal = stub_ai_removal

      connect_agent

      expect(response).to have_http_status(:bad_gateway)
      expect(answer).to eq('error' => 'agent_not_answered')
      expect(removal).to have_been_requested
      expect_nothing_left
    end

    it 'says the installation is not ready when it has no encryption keys, before any request' do
      registration = stub_ai_registration
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      connect_agent

      expect(response).to have_http_status(:service_unavailable)
      expect(answer).to eq('error' => 'not_ready')
      expect(registration).not_to have_been_requested
      expect_nothing_left
    end
  end

  describe 'a body that does not read' do
    it 'refuses another contract version, a body that is not JSON and a missing token, before any request' do
      registration = stub_ai_registration

      connect_agent(with: { contract: 2 })
      expect(answer).to include('error' => 'contract_unsupported')
      connect_agent(body: 'not json')
      expect(answer).to include('error' => 'contract_unsupported')
      connect_agent(body: '[1]')
      expect(answer).to include('error' => 'contract_unsupported')
      connect_agent(with: { token: '' })
      expect(answer).to include('error' => 'token_invalid')
      connect_agent(with: { token: nil })
      expect(answer).to include('error' => 'token_invalid')
      connect_agent(with: { token: 'x' * 4097 })
      expect(answer).to include('error' => 'token_invalid')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(registration).not_to have_been_requested
      expect(agent_bots_of(account)).to be_empty
    end
  end
end
