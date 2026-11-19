# frozen_string_literal: true

# One erasure request of the store app (capability app-store-erasure,
# contract in docs/app-store-erasure.md): Shopify asked to erase a store, to
# erase one shopper, or to provide one shopper's data. The record outlives
# what it erased, so it names the account, the ticket and the people by id
# only.
#
# A store's request follows the store: `scheduled` until its time has come,
# `erasing` while the account is destroyed, `erased` afterwards, or
# `cancelled` when the store installed the app again in time. A request about
# a shopper is `waiting`, `held` or `done`; its email and phone are readable,
# encrypted at rest, only until it is done.
#
# Completed rows are kept for KEEP and then removed by the daily erasure run
# (Inclamo::ErasureCheckJob); a held row is kept for as long as the hold stands.
class Inclamo::ErasureRequest < ApplicationRecord
  KINDS = %w[store shopper_erasure shopper_data_request].freeze
  STORE_STATES = %w[scheduled erasing erased cancelled].freeze
  SHOPPER_STATES = %w[waiting held done].freeze
  COMPLETED_STATES = %w[erased cancelled done].freeze
  KEEP = 90.days

  encrypts :email, :phone, :hold_reason

  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: ->(request) { request.store? ? STORE_STATES : SHOPPER_STATES } }
  validates :shop_domain, presence: true

  scope :stores, -> { where(kind: 'store') }
  scope :shoppers, -> { where.not(kind: 'store') }
  scope :completed_before, ->(time) { where(state: COMPLETED_STATES).where(completed_at: ...time) }

  # The store's erasure that waits for its time, if any. (One under way names
  # the account it destroys, which the store may no longer have.)
  def self.scheduled_store(shop_domain)
    stores.find_by(shop_domain: shop_domain, state: 'scheduled')
  end

  def store?
    kind == 'store'
  end

  def shopper_erasure?
    kind == 'shopper_erasure'
  end

  def data_request?
    kind == 'shopper_data_request'
  end

  def waiting?
    state == 'waiting'
  end

  def held?
    state == 'held'
  end

  def done?
    state == 'done'
  end
end
