# frozen_string_literal: true

# The account's link to the AI agent, one per account. The agent bot, its token
# and its secret live in Chatwoot's own tables; this record holds what the
# helpdesk needs to find them and what the AI agent page shows. Connect and
# disconnect through Inclamo::Ai::Connect and Inclamo::Ai::Disconnect, and
# change the inboxes through Inclamo::Ai::ChangeInboxes.
class Inclamo::AiConnection < ApplicationRecord
  STATES = %w[connected failing disconnected].freeze
  ACTIVE_STATES = %w[connected failing].freeze
  # The door the connection came through: an administrator with a code on the
  # "AI agent" page, or the store app (capability app-agent-auto-connection).
  VIAS = %w[page app].freeze
  # Why the last change of the agent's inboxes was not completed
  # (capability agent-inbox-selection; Inclamo::Ai::ChangeInboxes).
  INBOX_CHANGE_ERRORS = %w[not_applied not_applied_service_not_told storefront_not_added].freeze

  belongs_to :account
  belongs_to :agent_bot, optional: true
  belongs_to :phone_inbox, class_name: 'Inbox', optional: true
  # Empty for a connection the store app made: no person made it.
  belongs_to :connected_by, class_name: 'User', optional: true

  enum :state, STATES.index_with(&:itself)

  scope :active, -> { where(state: ACTIVE_STATES) }

  validates :account_id, uniqueness: true
  validates :service_url, presence: true
  validates :connected_via, inclusion: { in: VIAS }
  validates :inbox_change_error, inclusion: { in: INBOX_CHANGE_ERRORS }, allow_nil: true
  # The bot's secret is stored encrypted only when keys are configured
  # (Chatwoot's WebhookSecretable): without them a connection is refused.
  validate :encryption_must_be_configured, unless: :disconnected?

  after_save :forget_answering_inbox_ids

  # The connection that is on for the account, or nil.
  def self.active_for(account_id)
    active.find_by(account_id: account_id)
  end

  def active?
    ACTIVE_STATES.include?(state)
  end

  # The inboxes chosen for the agent as they were last written: at the
  # connection, or by the latest change of the inboxes.
  def connected_inbox_ids
    Array(inbox_ids).map(&:to_i)
  end

  # The inboxes the agent answers in now (agent-inbox-selection, design D7):
  # the chosen ones that still carry the connection's bot, in the chosen
  # order. An inbox the team deleted, or whose bot was changed in Chatwoot's
  # own inbox settings, stops counting at once; an inbox given the bot there
  # does not start counting. Asked of the database once per record.
  def answering_inbox_ids
    return [] unless active? && agent_bot_id.present?

    @answering_inbox_ids ||= begin
      chosen = connected_inbox_ids
      attached = chosen.empty? ? [] : AgentBotInbox.active.joins(:inbox).where(agent_bot_id: agent_bot_id, inbox_id: chosen).pluck(:inbox_id)
      chosen & attached
    end
  end

  def covers?(inbox_id)
    active? && answering_inbox_ids.include?(inbox_id.to_i)
  end

  def reload(...)
    forget_answering_inbox_ids
    super
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

  def forget_answering_inbox_ids
    @answering_inbox_ids = nil
  end

  def encryption_must_be_configured
    errors.add(:base, 'encryption is not configured on this installation') unless Chatwoot.encryption_configured?
  end
end
