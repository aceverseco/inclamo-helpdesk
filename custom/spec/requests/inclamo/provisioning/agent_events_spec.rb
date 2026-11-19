# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# Every call of the app about the agent is recorded with its time, the store's
# domain and its outcome, and without any token (design D9, task 3.10).
RSpec.describe 'App agent connection: the record of attempts', type: :request do
  include_context 'with the store app and the AI service'

  let(:store) { ProvisioningRequests::STORE }
  let(:account) { provisioned.account }

  before { provision }

  def last_events(count)
    Inclamo::ProvisioningEvent.order(:id).last(count).map { |event| [event.outcome, event.shop_domain] }
  end

  it 'records each call with its outcome and the store' do
    stub_ai_registration
    stub_ai_removal

    connect_agent
    connect_agent
    ask_agent_status
    disconnect_agent

    expect(last_events(4)).to eq([['agent_connected', store], ['agent_existed', store], ['agent_status', store], ['agent_disconnected', store]])
    expect(Inclamo::ProvisioningEvent.order(:id).last(4).map(&:created_at)).to all(be_within(1.minute).of(Time.current))
  end

  it 'records a refusal by the AI service, one by the helpdesk, and an AI service that did not answer' do
    stub_ai_registration(status: 410, body: { error: 'invalid_token', message: 'Expired.' })
    connect_agent
    connect_agent(with: { service_url: 'https://attacker.example.net' })
    stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_timeout
    connect_agent
    connect_agent('unknown-store.myshopify.com')
    ask_agent_status('unknown-store.myshopify.com')

    expect(last_events(5)).to eq([
                                   ['agent_refused', store], ['agent_refused', store], ['agent_not_answered', store],
                                   ['agent_refused', 'unknown-store.myshopify.com'], ['agent_status', 'unknown-store.myshopify.com']
                                 ])
  end

  it 'keeps no token, secret or signature in any record' do
    stub_ai_registration(status: 410, body: { error: 'invalid_token', message: 'Expired.' })
    connect_agent
    stub_ai_registration
    connect_agent
    bot = AgentBot.find(connection_of(account).agent_bot_id)

    values = Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values.map(&:to_s) }
    [AgentProvisioningRequests::PAIRING_TOKEN, bot.access_token.token, bot.secret, ProvisioningRequests::SECRET].each do |secret|
      expect(values.join("\n")).not_to include(secret)
    end
    expect(Inclamo::ProvisioningEvent.column_names).to contain_exactly('id', 'shop_domain', 'outcome', 'request_id', 'account_id', 'created_at')
  end

  it 'answers a repeated request id from the stored answer and records it again with the same outcome' do
    stub_ai_registration
    request_id = SecureRandom.uuid

    connect_agent(request_id: request_id)
    first = response.parsed_body
    connect_agent(request_id: request_id)

    expect(response.parsed_body).to eq(first)
    expect(response).to have_http_status(:created)
    expect(last_events(2)).to eq([['agent_connected', store], ['agent_connected', store]])
    expect(agent_bots_of(account).count).to eq(1)
  end
end
