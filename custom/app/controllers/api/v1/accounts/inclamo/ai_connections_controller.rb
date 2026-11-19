# frozen_string_literal: true

# The account's AI agent connection, for administrators only: what the AI
# agent page shows, connecting with a code, changing the inboxes of a
# connection (capability agent-inbox-selection) and disconnecting (design D9).
# No answer carries the bot's token or secret, the code, or a conversation's content.
class Api::V1::Accounts::Inclamo::AiConnectionsController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  ERROR_STATUS = {
    forbidden: :forbidden,
    not_connected: :not_found,
    already_connected: :conflict,
    busy: :conflict,
    not_answered: :bad_gateway,
    # The AI service accepted a change the helpdesk could not apply; the
    # connection's `inbox_change_error` says so on the next read.
    not_applied: :internal_server_error
  }.freeze
  INBOX_ID = /\A[1-9]\d{0,17}\z/

  def show
    render json: present
  end

  def create
    ::Inclamo::Ai::Connect.call(account: Current.account, user: Current.user, code: params[:connection_code], inbox_ids: params[:inbox_ids])
    render json: present, status: :created
  rescue ::Inclamo::Ai::Error::Refused => e
    render json: { error: 'refused', message: e.message, service_error: e.service_error }, status: :unprocessable_entity
  rescue ::Inclamo::Ai::Error => e
    refuse(e.code)
  end

  # PATCH { inbox_ids: [...] }: the whole list of inboxes the agent answers in
  # after the change, possibly empty. The AI service is told first.
  def update
    ids = requested_inbox_ids
    return refuse(:invalid_inbox) unless ids

    ::Inclamo::Ai::ChangeInboxes.call(account: Current.account, user: Current.user, inbox_ids: ids)
    render json: present
  rescue ::Inclamo::Ai::Error::Refused => e
    render json: { error: 'refused', message: e.message, service_error: e.service_error }, status: :unprocessable_entity
  rescue ::Inclamo::Ai::Error => e
    refuse(e.code)
  end

  def destroy
    record = ::Inclamo::Ai::Disconnect.call(account: Current.account)
    render json: present.merge(ai_service_told: record.removal_error.nil?)
  rescue ::Inclamo::Ai::Error => e
    refuse(e.code)
  end

  private

  # A list of inbox ids, or nil when the body names none or names something else.
  def requested_inbox_ids
    ids = params[:inbox_ids]
    return [] if ids.is_a?(Array) && ids.empty?
    return unless ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) ? id.positive? : INBOX_ID.match?(id.to_s) }

    ids.map(&:to_i)
  end

  def record
    @record ||= ::Inclamo::AiConnection.find_by(account_id: Current.account.id)
  end

  def require_administrator
    refuse(:forbidden) unless Current.account_user&.administrator?
  end

  def present
    @record = nil
    active = record&.active?
    {
      connected: active || false,
      state: record&.state || 'never_connected',
      encryption_configured: Chatwoot.encryption_configured?,
      get_agent_url: ENV.fetch('INCLAMO_AI_AGENT_URL', 'https://inclamo.com'),
      inboxes: inboxes,
      connection: active ? connection_details : nil,
      last_disconnection: record&.disconnected? ? { disconnected_at: record.disconnected_at, ai_service_told: record.removal_error.nil? } : nil
    }
  end

  def connection_details
    {
      state: record.state,
      # The inboxes the agent answers in now (AiConnection#answering_inbox_ids).
      inbox_ids: record.answering_inbox_ids,
      phone_inbox_id: record.phone_inbox_id,
      connected_at: record.connected_at,
      connected_by: record.connected_by&.name,
      # `app` for a connection the store app made: no person made it.
      connected_via: record.connected_via,
      last_delivered_at: record.last_delivered_at,
      last_failed_at: record.last_failed_at,
      last_error: record.last_error,
      last_reply_at: record.last_reply_at,
      # Why the last change of the inboxes was not completed, or nil.
      inbox_change_error: record.inbox_change_error
    }
  end

  # Every inbox the agent could answer in: all but the Phone inbox. One with
  # another bot or Dialogflow is listed and cannot be picked; the agent's own
  # bot is not another. `pending_for_agent` counts the inbox's Pending
  # conversations whose AI assignee is the agent's bot: those a change that
  # removes the inbox gives to the team.
  def inboxes
    active = record&.active?
    connected = active ? record.answering_inbox_ids : []
    own_bot_id = active ? record.agent_bot_id : nil
    pending = pending_for_agent(own_bot_id)
    Current.account.inboxes.order(:id).reject { |inbox| inbox.id == record&.phone_inbox_id }.map do |inbox|
      other_bot = ::Inclamo::Ai::InboxChoice.other_provider(inbox, own_bot_id)
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, connected: connected.include?(inbox.id), other_bot: other_bot,
        selectable: other_bot.nil?, pending_for_agent: pending.fetch(inbox.id, 0) }
    end
  end

  def pending_for_agent(bot_id)
    return {} unless bot_id

    Current.account.conversations.where(status: :pending, assignee_agent_bot_id: bot_id, ai_assignee_type: 'AgentBot').group(:inbox_id).count
  end

  def refuse(code)
    code = code.to_sym
    render json: { error: code, message: I18n.t("inclamo.ai_connection.errors.#{code}") }, status: ERROR_STATUS.fetch(code, :unprocessable_entity)
  end
end
