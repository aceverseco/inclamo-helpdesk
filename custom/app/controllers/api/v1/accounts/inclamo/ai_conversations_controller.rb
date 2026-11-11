# frozen_string_literal: true

# The AI agent's calls of docs/ai-connector.md §5: a conversation's public
# history with its files, the protected reply, `inclamo_` labels and the
# order authority's calls.
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
  rescue_from ::Inclamo::Ai::OrderAuthority::Refused, with: :authority_refused
  rescue_from ::Inclamo::Shopify::Error, with: :authority_store_failed
  rescue_from ActiveRecord::RecordInvalid, with: :authority_invalid

  def orders
    render json: authority.context
  end

  def propose
    record = authority.propose(params.permit(:action_name, :request_id, :order_id, :customer_id, :note, address: {}, params: {}).to_h)
    render json: record.present, status: :created
  end

  def proposal
    render json: find_proposal.present
  end

  def execute
    render json: authority.execute(find_proposal, autonomous: true).present
  end

  def messages
    render json: ::Inclamo::Ai::History.new(@conversation, @connection, limit: params[:limit])
  end

  # The protected reply (ai-reply-ownership): posted only while the
  # conversation is Pending, checked and saved under the conversation's lock.
  def reply
    content = params[:content]
    return refuse(:empty_reply, :unprocessable_entity) unless content.is_a?(String) && content.strip.present?

    protected_reply = ::Inclamo::Ai::ProtectedReply.new(conversation: @conversation, bot: @resource, content: content)
    message = protected_reply.perform
    return refuse(:conversation_not_pending, :conflict, status: protected_reply.status) unless message

    render json: { id: message.id, created_at: message.created_at }, status: :created
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

  def authority
    ::Inclamo::Ai::OrderAuthority.new(account: Current.account, conversation: @conversation, bot: @resource)
  end

  def find_proposal
    ::Inclamo::AiProposal.find_by!(id: params[:id], account_id: Current.account.id, conversation_id: @conversation.id, agent_bot_id: @resource.id)
  end

  def authority_refused(error)
    render json: { error: error.message }, status: :conflict
  end

  def authority_store_failed(_error)
    render json: { error: 'store_unavailable' }, status: :bad_gateway
  end

  def authority_invalid(_error)
    render json: { error: 'invalid_request' }, status: :unprocessable_entity
  end

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
    refuse(code, :unprocessable_entity, extra)
  end

  def refuse(code, http_status, extra = {})
    render json: { error: code, message: I18n.t("inclamo.ai_agent.errors.#{code}") }.merge(extra), status: http_status
  end
end
