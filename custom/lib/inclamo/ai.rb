# frozen_string_literal: true

module Inclamo
  # The helpdesk's side of the AI agent: connecting an account to the AI
  # service through Chatwoot's agent bot, what the agent may read and label,
  # and the delivery health of the link. The contract with the AI service is
  # docs/ai-connector.md.
  module Ai
    CONTRACT = 1
    CODE_PREFIX = 'aic1.'
    # Time the AI service has to answer a registration or a removal.
    TIME_LIMIT = 10

    # Labels the agent may add: `inclamo_` and Chatwoot's label form
    # (app/models/label.rb, lib/regex_helper.rb), lower case only.
    LABEL_FORMAT = /\Ainclamo_[a-z0-9_-]+\z/
    LABEL_MAX_LENGTH = 100
    LABELS_PER_REQUEST = 20
    # Chatwoot's default label colour. Which colour marks the agent's labels is
    # an open question of the design; it is set here only.
    LABEL_COLOR = '#1f93ff'

    # The labels the AI service uses today, created at connection with their
    # meanings (design D7). Labels per request type are created when first added.
    LABELS = {
      'inclamo_handover' => 'The team has the conversation from the AI agent',
      'inclamo_resolved' => 'The AI agent closed the conversation',
      'inclamo_escalation' => 'The AI agent filed a request for the team',
      'inclamo_error' => 'The AI agent failed and handed the conversation over',
      'inclamo_limit' => 'The AI agent reached its turn limit and handed over',
      'inclamo_offline' => 'The shopper wrote through an offline form',
      'inclamo_urgent' => 'Urgent: the AI agent raised the priority to urgent',
      'inclamo_request_ready' => 'A filed request with all the data it needs',
      'inclamo_request_incomplete' => 'A filed request that lacks some data',
      'inclamo_call' => 'A phone call with the AI agent',
      'inclamo_inbound' => 'The shopper called the store',
      'inclamo_outbound' => 'The AI agent called the shopper',
      'inclamo_web' => "A call from the store's website",
      'inclamo_callback' => 'The shopper asked to be called back',
      'inclamo_parts_request' => 'The caller asked for parts',
      'inclamo_transferred' => 'The call was transferred to a person',
      'inclamo_no_conversation' => 'The call ended before a conversation took place',
      'inclamo_match_ambiguous' => 'More than one contact matched the caller',
      'inclamo_no_caller_id' => 'The call came without a number'
    }.freeze
    ADDED_LABEL_DESCRIPTION = 'Set by the AI agent'

    # One connection or disconnection of an account at a time. The lock is
    # kept in Redis, so no database transaction stays open while the AI
    # service is asked.
    def self.with_account_lock(account, seconds: 60)
      key = "inclamo:ai:#{account.id}:connection"
      owner = SecureRandom.hex(8)
      raise Error::Busy, 'the connection of this account is being changed' unless ::Redis::Alfred.set(key, owner, nx: true, ex: seconds)

      begin
        yield
      ensure
        ::Redis::Alfred.delete_if_equals(key, owner)
      end
    end

    # Removes an agent bot so that its token is refused at once: Chatwoot
    # destroys a bot's token and inbox links asynchronously
    # (app/models/concerns/access_tokenable.rb:4-5, app/models/agent_bot.rb),
    # which would leave them usable for a moment.
    def self.remove_bot(bot)
      return unless bot

      AgentBotInbox.where(agent_bot_id: bot.id).destroy_all
      AccessToken.where(owner_type: 'AgentBot', owner_id: bot.id).destroy_all
      AgentBot.find_by(id: bot.id)&.destroy!
    end

    def self.private_network_allowed?
      SafeFetch.allow_private_network?
    end

    # HTTPS, or HTTP where Chatwoot is allowed to reach private networks (a test stack).
    def self.acceptable_url?(value)
      uri = URI.parse(value.to_s)
      return false if uri.host.blank?

      uri.is_a?(URI::HTTPS) || (uri.is_a?(URI::HTTP) && private_network_allowed?)
    rescue URI::InvalidURIError
      false
    end
  end
end
