# frozen_string_literal: true

# One provisioning attempt: the time, the store's domain, the outcome and the
# request id. Never the person's email or name, the signature, the body or the
# password link.
class Inclamo::ProvisioningEvent < ApplicationRecord
  OUTCOMES = %w[created existed restored suspended none refused limited].freeze
  KEEP = 90.days
  DOMAIN = /\A[a-z0-9][a-z0-9.-]{0,254}\z/
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  validates :outcome, inclusion: { in: OUTCOMES }

  scope :expired, ->(now = Time.current) { where(created_at: ...(now - KEEP)) }

  # Refused attempts are recorded too, and their address and request id come
  # from whoever sent them: only a value that reads as a domain or a UUID is
  # kept. A failure to record never fails the request it describes.
  def self.record(outcome:, shop_domain:, request_id:)
    domain = shop_domain.to_s.downcase
    id = request_id.to_s.downcase
    create!(outcome: outcome, shop_domain: (domain if DOMAIN.match?(domain)), request_id: (id if UUID.match?(id)),
            created_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[inclamo provisioning] attempt not recorded: #{e.class}")
    nil
  end
end
