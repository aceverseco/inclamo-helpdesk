# frozen_string_literal: true

class Inclamo::AiPolicy < ApplicationRecord
  MODES = %w[forbidden propose autonomous].freeze
  ORDER_ACTIONS = %w[address edit_items cancel refund replacement order_tags order_note].freeze
  MONEY_ACTIONS = (ORDER_ACTIONS + %w[new_order discount]).freeze
  STATES = %w[UNFULFILLED PARTIALLY_FULFILLED FULFILLED RESTOCKED ON_HOLD SCHEDULED IN_PROGRESS].freeze
  FIELDS = %w[max_amount currency allowed_states max_percentage].freeze
  belongs_to :account
  validates :action, inclusion: { in: Inclamo::ActionPermissions::ACTIONS }, uniqueness: { scope: :account_id }
  validates :mode, inclusion: { in: MODES }
  validate :valid_limits

  def self.for(account, action)
    find_by(account_id: account.id, action: action) || new(account: account, action: action)
  end

  def as_json(*)
    { action: action, mode: mode, limits: limits }
  end

  private

  def valid_limits
    unless limits.is_a?(Hash) && (limits.keys - FIELDS).empty?
      errors.add(:limits, 'contain unsupported restrictions')
      return
    end
    return unless mode == 'autonomous'

    if MONEY_ACTIONS.include?(action)
      currency = Inclamo::ShopifyConnection.find_by(account_id: account_id)&.shop_currency
      errors.add(:limits, 'must use the connected store currency') unless currency.present? && limits['currency'] == currency
      errors.add(:limits, 'must include a positive maximum amount') unless decimal?(limits['max_amount'])
    end
    if ORDER_ACTIONS.include?(action)
      states = limits['allowed_states']
      errors.add(:limits, 'must select valid fulfillment states') unless states.is_a?(Array) && states.any? && (states - STATES).empty?
    end
    return unless action == 'discount'

    value = limits['max_percentage']
    errors.add(:limits, 'must include a maximum percentage between 0 and 100') unless decimal?(value, zero: true) && value.to_d <= 100
  end

  def decimal?(value, zero: false)
    value.to_s.match?(/\A\d{1,9}(\.\d{1,2})?\z/) && (zero ? value.to_d >= 0 : value.to_d.positive?)
  end
end
