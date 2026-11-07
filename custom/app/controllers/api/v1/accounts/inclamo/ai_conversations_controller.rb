# frozen_string_literal: true

# The two calls of the AI agent (design D6; docs/ai-connector.md §5): a
# conversation's public history with its files, and adding `inclamo_` labels.
#
# Only the agent bot of the account's connection may call them, with its
# token, and only for conversations of the connected inboxes. That is stricter
# than Chatwoot's own rule for bots, which lets a bot act on any conversation
# of its account (app/policies/conversation_policy.rb:11, :24-25). A user's
# token, a dashboard session, another bot's token or the bot of a
# disconnected account is refused (401); a conversation outside the connected
# inboxes, or one that does not exist, is refused (403) with nothing in the answer.
class Api::V1::Accounts::Inclamo::AiConversationsController < Api::V1::Accounts::BaseController
  # Chatwoot's list of what a bot may call does not name these endpoints; the
  # check below replaces it.
  skip_before_action :validate_bot_access_token!
  before_action :require_connected_bot
  before_action :require_connected_conversation

  def messages
    render json: ::Inclamo::Ai::History.new(@conversation, @connection, limit: params[:limit])
  end

  def labels
    names = params[:add]
    names = names.is_a?(Array) ? names.map { |name| name.is_a?(String) ? name.strip : name } : nil
    return refuse_labels(:no_labels) if names.blank?
    return refuse_labels(:too_many_labels) if names.size > ::Inclamo::Ai::LABELS_PER_REQUEST

    invalid = names.reject { |name| ::Inclamo::Ai::Labels.valid_name?(name) }
    return refuse_labels(:invalid_label, invalid: invalid.map(&:to_s).first(5)) if invalid.any?

    render json: { labels: ::Inclamo::Ai::Labels.add(@conversation, names.uniq) }
  end

  private

  def require_connected_bot
    bot = @resource if authenticate_by_access_token? && @resource.is_a?(AgentBot)
    @connection = ::Inclamo::AiConnection.active_for(Current.account.id)
    return if bot && @connection&.agent_bot?(bot)

    render json: { error: 'unauthorized', message: I18n.t('inclamo.ai_agent.errors.unauthorized') }, status: :unauthorized
  end

  def require_connected_conversation
    @conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
    return if @conversation && @connection.covers?(@conversation.inbox_id)

    render json: { error: 'forbidden', message: I18n.t('inclamo.ai_agent.errors.forbidden') }, status: :forbidden
  end

  def refuse_labels(code, extra = {})
    render json: { error: code, message: I18n.t("inclamo.ai_agent.errors.#{code}") }.merge(extra), status: :unprocessable_entity
  end
end
