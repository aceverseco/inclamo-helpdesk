# frozen_string_literal: true

# Files a finished call of the AI phone agent as a conversation of the
# account's Phone inbox (docs/ai-connector-calls.md).
#
# Only the agent bot of the account's connection may call it, with its token.
# Chatwoot's list of what a bot may call does not name this endpoint; the
# check below replaces it. A refusal never repeats a part of the call, and the
# log keeps the call's id, the code and counts only (the call's fields are
# filtered from the request log in custom/config/overlay.rb).
class Api::V1::Accounts::Inclamo::AiCallsController < Api::V1::Accounts::BaseController
  skip_before_action :validate_bot_access_token!
  before_action :require_connected_bot
  rescue_from ::Inclamo::Ai::Calls::Refused, with: :refused
  # Chatwoot's own answer to a record it refuses would name the field's content.
  rescue_from(ActiveRecord::RecordInvalid) { refused(::Inclamo::Ai::Calls::Refused.new(:invalid_call)) }

  def create
    filing = ::Inclamo::Ai::Calls::Filing.read(request.request_parameters)
    result = ::Inclamo::Ai::Calls::FileCall.call(account: Current.account, connection: @connection, bot: @resource, filing: filing)
    Rails.logger.info("[inclamo] call #{filing.call_id} #{result.found ? 'found' : 'filed'}: #{filing.counts.to_json}")
    render json: {
      conversation_id: result.conversation.display_id, contact_id: result.contact_id, found: result.found,
      matched_by: result.matched_by, labels_added: result.labels_added
    }, status: result.found ? :ok : :created
  end

  private

  # A token that is no agent bot's is unauthorised, as is the token of a bot
  # other than the connection's. A bot of an account whose AI agent is not
  # connected, or whose Phone inbox is gone, gets `not_connected`.
  def require_connected_bot
    bot = @resource if authenticate_by_access_token? && @resource.is_a?(AgentBot)
    return render_unauthorized_call unless bot

    @connection = ::Inclamo::AiConnection.active_for(Current.account.id)
    return refuse(:not_connected, :conflict) unless @connection&.phone_inbox
    return render_unauthorized_call unless @connection.agent_bot?(bot)
  end

  def render_unauthorized_call
    render json: { error: 'unauthorized', message: I18n.t('inclamo.ai_agent.errors.unauthorized') }, status: :unauthorized
  end

  def refused(error)
    call_id = params[:call_id].to_s
    call_id = '-' unless ::Inclamo::Ai::Calls::CALL_ID_FORMAT.match?(call_id)
    Rails.logger.info("[inclamo] call #{call_id} refused: #{error.code}")
    refuse(error.code, :unprocessable_entity)
  end

  def refuse(code, http_status)
    render json: { error: code, code: code, message: I18n.t("inclamo.ai_calls.errors.#{code}") }, status: http_status
  end
end
