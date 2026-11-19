# frozen_string_literal: true

# One provisioning attempt: the time, the store's domain, the outcome and the
# request id. Never the person's email or name, the signature, the body, the
# password link or a website token. The outcomes that begin with `chat_` are
# those of the storefront chat's request (docs/app-storefront-chat.md), and those
# that begin with `agent_` the AI agent's three calls (docs/app-agent-connection.md).
# Those that begin with `key_` are the helpdesk's own requests for a store key
# (docs/app-store-access.md), which also name the account.
class Inclamo::ProvisioningEvent < ApplicationRecord
  OUTCOMES = %w[created existed restored suspended none refused limited chat_created chat_existed chat_refused
                agent_connected agent_existed agent_refused agent_not_answered agent_disconnected agent_status].freeze
  KEEP = 90.days
  DOMAIN = /\A[a-z0-9][a-z0-9.-]{0,254}\z/
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  KEY_OUTCOME = /\Akey_(?:granted|no_answer|refused:[a-z0-9_]{1,40}|invalid:[a-z_]{1,40})\z/

  validates :outcome, inclusion: { in: OUTCOMES }, unless: -> { KEY_OUTCOME.match?(outcome.to_s) }

  scope :expired, ->(now = Time.current) { where(created_at: ...(now - KEEP)) }

  # Refused attempts are recorded too, and their address and request id come
  # from whoever sent them: only a value that reads as a domain or a UUID is
  # kept. A failure to record never fails the request it describes.
  def self.record(outcome:, shop_domain:, request_id:, account_id: nil)
    domain = shop_domain.to_s.downcase
    id = request_id.to_s.downcase
    create!(outcome: outcome, shop_domain: (domain if DOMAIN.match?(domain)), request_id: (id if UUID.match?(id)),
            account_id: account_id, created_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[inclamo provisioning] attempt not recorded: #{e.class}")
    nil
  end
end
