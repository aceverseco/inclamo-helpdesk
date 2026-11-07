# frozen_string_literal: true

# The account's AI agent connection, for administrators only: what the AI
# agent page shows, connecting with a code and disconnecting (design D9). No
# answer carries the bot's token or secret, the code, or a conversation's content.
class Api::V1::Accounts::Inclamo::AiConnectionsController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  ERROR_STATUS = {
    forbidden: :forbidden,
    not_connected: :not_found,
    already_connected: :conflict,
    busy: :conflict,
    not_answered: :bad_gateway
  }.freeze

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

  def destroy
    record = ::Inclamo::Ai::Disconnect.call(account: Current.account)
    render json: present.merge(ai_service_told: record.removal_error.nil?)
  rescue ::Inclamo::Ai::Error => e
    refuse(e.code)
  end

  private

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
      inbox_ids: record.connected_inbox_ids,
      phone_inbox_id: record.phone_inbox_id,
      connected_at: record.connected_at,
      connected_by: record.connected_by&.name,
      last_delivered_at: record.last_delivered_at,
      last_failed_at: record.last_failed_at,
      last_error: record.last_error,
      last_reply_at: record.last_reply_at
    }
  end

  # Every inbox the agent could answer in: all but the Phone inbox. One with
  # another bot or Dialogflow is listed and cannot be picked.
  def inboxes
    connected = record&.active? ? record.connected_inbox_ids : []
    Current.account.inboxes.order(:id).reject { |inbox| inbox.id == record&.phone_inbox_id }.map do |inbox|
      other_bot = connected.include?(inbox.id) ? nil : inbox.conflicting_bot_provider(:inclamo)
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, connected: connected.include?(inbox.id), other_bot: other_bot, selectable: other_bot.nil? }
    end
  end

  def refuse(code)
    code = code.to_sym
    render json: { error: code, message: I18n.t("inclamo.ai_connection.errors.#{code}") }, status: ERROR_STATUS.fetch(code, :unprocessable_entity)
  end
end
