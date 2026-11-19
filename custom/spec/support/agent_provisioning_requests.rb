# frozen_string_literal: true

require Rails.root.join('custom/spec/support/provisioning_requests')
require Rails.root.join('custom/spec/support/ai_service_stubs')

# Plays the store app's three calls about a store's AI agent
# (docs/app-agent-connection.md) on top of ProvisioningRequests, which signs
# them, and AiServiceStubs, which plays the AI service.
module AgentProvisioningRequests
  PAIRING_TOKEN = 'one-time-pairing-token-for-specs'

  def agent_body(**top)
    { contract: 1, service_url: AiServiceStubs::AI_SERVICE_URL, token: PAIRING_TOKEN }.merge(top)
  end

  # PUT stores/{domain}/agent. `with` is laid over a valid body; `body` replaces it.
  def connect_agent(domain = ProvisioningRequests::STORE, with: {}, **options)
    body = options.key?(:body) ? options.delete(:body) : agent_body(**with)
    provisioning_call(:put, domain, body: body, suffix: '/agent', **options)
  end

  def ask_agent_status(domain = ProvisioningRequests::STORE, **)
    provisioning_call(:get, domain, suffix: '/agent', **)
  end

  def disconnect_agent(domain = ProvisioningRequests::STORE, **)
    provisioning_call(:delete, domain, suffix: '/agent', **)
  end

  def connection_of(account)
    Inclamo::AiConnection.find_by(account_id: account.id)
  end

  def agent_bots_of(account)
    AgentBot.where(account_id: account.id)
  end

  # What the agent's connection makes in an account, to show a refusal made none.
  def made_for_agent(account)
    {
      bots: agent_bots_of(account).count, tokens: AccessToken.where(owner_type: 'AgentBot').count,
      inboxes: account.inboxes.count, labels: account.labels.count, links: AgentBotInbox.count
    }
  end

  # The account's connection lock held as by another connection under way.
  def hold_connection_lock(account)
    Redis::Alfred.set("inclamo:ai:#{account.id}:connection", 'held-by-a-spec', nx: true, ex: 60)
  end

  def release_connection_lock(account)
    Redis::Alfred.delete("inclamo:ai:#{account.id}:connection")
  end
end

# An installation whose operator set the shared secret and allowed the specs'
# AI service address; the AI service is reached through WebMock.
RSpec.shared_context 'with the store app and the AI service' do
  include_context 'with app provisioning'
  include AiServiceStubs
  include AgentProvisioningRequests

  around do |example|
    with_modified_env(INCLAMO_APP_AGENT_SERVICE_URLS: AiServiceStubs::AI_SERVICE_URL) { example.run }
  end

  before { resolve_ai_service_publicly }
end
