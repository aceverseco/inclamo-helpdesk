# frozen_string_literal: true

# The one Shopify store an account is connected to, and the credentials of the
# merchant's own custom app. Talk to the store through
# Inclamo::Shopify::StoreConnection, which hands out a valid token.
class Inclamo::ShopifyConnection < ApplicationRecord
  AUTH_KINDS = %w[client_credentials legacy_token].freeze
  READ_SCOPES = %w[read_customers read_orders].freeze
  ACTION_SCOPES = {
    'cancel' => %w[write_orders],
    'refund' => %w[write_orders],
    'address' => %w[write_orders],
    # read_products: the items a replacement keeps are named to the store by
    # their variants, and a variant can only be read with that scope.
    'replacement' => %w[write_orders write_draft_orders read_products]
  }.freeze

  belongs_to :account

  # Declared unconditionally: without encryption keys a save fails instead of
  # storing plain text. The validation below turns that into a clear refusal.
  encrypts :client_secret
  encrypts :access_token

  enum :status, { working: 'working', broken: 'broken' }
  enum :customer_data_mode, { full: 'full', limited: 'limited' }, prefix: :customer_data
  enum :auth_kind, AUTH_KINDS.index_with(&:itself)

  validates :account_id, uniqueness: true
  validates :shop_domain, format: { with: Inclamo::Shopify::DOMAIN_FORMAT }
  validates :auth_kind, :api_version, presence: true
  validates :client_id, :client_secret, presence: true, if: :client_credentials?
  validates :access_token, presence: true, if: :legacy_token?
  validate :encryption_must_be_configured

  def missing_scopes_for(action)
    ACTION_SCOPES.fetch(action.to_s) - scopes
  end

  # Why an action cannot be performed with this connection, or nil.
  def unavailable_reason(action)
    return 'missing_scope' if missing_scopes_for(action).any?
    return 'customer_data_hidden' if action.to_s == 'address' && customer_data_limited?

    nil
  end

  def actions_report
    ACTION_SCOPES.keys.map do |action|
      reason = unavailable_reason(action)
      { name: action, available: reason.nil?, reason: reason, missing_scopes: missing_scopes_for(action) }
    end
  end

  private

  def encryption_must_be_configured
    errors.add(:base, 'encryption is not configured on this installation') unless Chatwoot.encryption_configured?
  end
end
