# frozen_string_literal: true

# The AI service as the helpdesk's specs see it: connection codes, its
# registration and removal endpoints, and an account connected to it.
module AiServiceStubs
  AI_SERVICE_URL = 'https://ai.example.com'
  AI_JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  def ai_code(service_url: AI_SERVICE_URL, token: 'one-time-token-for-specs', **extra)
    "aic1.#{Base64.urlsafe_encode64({ service_url: service_url, token: token }.merge(extra).to_json, padding: false)}"
  end

  # The SSRF filter resolves host names; specs have no DNS to ask.
  def resolve_ai_service_publicly
    allow(Inclamo::Ai::ServiceClient).to receive(:resolver).and_return(->(_host) { [IPAddr.new('93.184.216.34')] })
  end

  def stub_ai_registration(status: 201, body: { connection_id: 'conn-1', webhook_url: "#{AI_SERVICE_URL}/webhooks/conn-1" })
    stub_request(:post, "#{AI_SERVICE_URL}/connections")
      .to_return(status: status, body: body.is_a?(String) ? body : body.to_json, headers: AI_JSON_HEADERS)
  end

  def stub_ai_removal(status: 204, connection_id: 'conn-1')
    stub_request(:delete, "#{AI_SERVICE_URL}/connections/#{connection_id}").to_return(status: status)
  end

  # An account connected the way Inclamo::Ai::Connect leaves it, without the
  # AI service: the bot attached to `inboxes`, a Phone inbox, the record.
  def connect_ai_agent(account, inboxes, webhook_url: "#{AI_SERVICE_URL}/webhooks/conn-1")
    bot = create(:agent_bot, account: account, name: 'AI agent', outgoing_url: webhook_url)
    inboxes.each { |inbox| create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }
    phone = create(:channel_api, account: account, webhook_url: nil).inbox
    phone.update!(name: 'Phone')
    create(:inclamo_ai_connection, account: account, agent_bot_id: bot.id, phone_inbox_id: phone.id, inbox_ids: inboxes.map(&:id))
  end
end
