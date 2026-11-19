# frozen_string_literal: true

# The account of one Shopify store, made on the store app's request (see
# Inclamo::Provisioning). The unique indexes on the domain and on the account
# are what keeps one account per store; the model adds no uniqueness check of
# its own, so a concurrent insert fails in the database and nowhere earlier.
#
# `store_access_url` is the store app's address for this store's key requests
# (docs/app-store-access.md), as the app's latest request that gave one named
# it; empty when none did, and then the installation's configured address
# applies.
class Inclamo::ProvisionedAccount < ApplicationRecord
  STATES = %w[active suspended].freeze

  belongs_to :account, optional: true

  before_validation { self.shop_domain = shop_domain.to_s.strip.downcase }

  validates :shop_domain, format: { with: Inclamo::Provisioning::SHOP_DOMAIN }
  validates :state, inclusion: { in: STATES }

  def self.for_store(shop_domain)
    find_by(shop_domain: shop_domain.to_s.strip.downcase)
  end

  def active?
    state == 'active'
  end

  def suspended?
    state == 'suspended'
  end
end
