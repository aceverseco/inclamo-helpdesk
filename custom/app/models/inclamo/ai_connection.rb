# frozen_string_literal: true

# The account's link to the AI agent, one per account. The agent bot, its token
# and its secret live in Chatwoot's own tables; this record holds what the
# helpdesk needs to find them and what the AI agent page shows. Connect and
# disconnect through Inclamo::Ai::Connect and Inclamo::Ai::Disconnect.
class Inclamo::AiConnection < ApplicationRecord
  STATES = %w[connected failing disconnected].freeze
  ACTIVE_STATES = %w[connected failing].freeze

  belongs_to :account
  belongs_to :agent_bot, optional: true
  belongs_to :phone_inbox, class_name: 'Inbox', optional: true
  belongs_to :connected_by, class_name: 'User', optional: true

  enum :state, STATES.index_with(&:itself)

  scope :active, -> { where(state: ACTIVE_STATES) }

  validates :account_id, uniqueness: true
  validates :service_url, presence: true
  # The bot's secret is stored encrypted only when keys are configured
  # (Chatwoot's WebhookSecretable): without them a connection is refused.
  validate :encryption_must_be_configured, unless: :disconnected?

  # The connection that is on for the account, or nil.
  def self.active_for(account_id)
    active.find_by(account_id: account_id)
  end

  def active?
    ACTIVE_STATES.include?(state)
  end

  def connected_inbox_ids
    Array(inbox_ids).map(&:to_i)
  end

  def covers?(inbox_id)
    active? && connected_inbox_ids.include?(inbox_id.to_i)
  end

  def agent_bot?(sender)
    sender.is_a?(AgentBot) && agent_bot_id.present? && sender.id == agent_bot_id
  end

  # A delivery to the AI service went through. A failing connection is
  # connected again; a disconnected one stays as it is.
  def self.record_delivery(id, at: Time.current)
    active.where(id: id).update_all(last_delivered_at: at, state: 'connected', updated_at: at) # rubocop:disable Rails/SkipsModelValidations
  end

  # A delivery to the AI service failed with `kind` (an HTTP status or an error class).
  def self.record_failure(id, kind, at: Time.current)
    active.where(id: id).update_all(last_failed_at: at, last_error: kind.to_s.first(100), state: 'failing', updated_at: at) # rubocop:disable Rails/SkipsModelValidations
  end

  def self.record_reply(id, at: Time.current)
    active.where(id: id).update_all(last_reply_at: at, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def encryption_must_be_configured
    errors.add(:base, 'encryption is not configured on this installation') unless Chatwoot.encryption_configured?
  end
end
