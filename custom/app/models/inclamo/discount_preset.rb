# frozen_string_literal: true

# A discount an administrator allows agents to give: its name, a percentage
# or an amount off the whole order, an expiry in days (none: never expires),
# how many times its code may be used and for whom. See
# Inclamo::Shopify::Actions::Discount for the code made from it.
class Inclamo::DiscountPreset < ApplicationRecord
  KINDS = %w[percentage amount].freeze
  # customer: the conversation's matched customer only; anyone: any buyer, once each.
  AUDIENCES = %w[customer anyone].freeze
  NAME_LENGTH = 60
  MAX_DAYS = 3650
  MAX_USES = 10_000
  MAX_AMOUNT = 1_000_000_000
  FIELDS = %w[name kind value expires_in_days usage_limit audience].freeze

  belongs_to :account

  validates :name, presence: true, length: { maximum: NAME_LENGTH }
  validates :kind, inclusion: { in: KINDS }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :value, numericality: { greater_than: 0, less_than: MAX_AMOUNT }
  validates :value, numericality: { less_than_or_equal_to: 100 }, if: -> { kind == 'percentage' }
  validates :expires_in_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_DAYS }, allow_nil: true
  validates :usage_limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_USES }
  validate :value_in_cents

  scope :ordered, -> { order(:id) }

  def as_json(*)
    {
      id: id, name: name, kind: kind, value: value.to_s('F').sub(/\.0\z/, ''), expires_in_days: expires_in_days,
      usage_limit: usage_limit, audience: audience
    }
  end

  private

  # A value is kept to the cent; more digits would be rounded without saying.
  def value_in_cents
    raw = value_before_type_cast
    return if errors.include?(:value) || raw.nil?
    return if raw.is_a?(Numeric) ? raw.to_d.round(2) == raw.to_d : raw.to_s.strip.match?(/\A\d+(\.\d{1,2})?\z/)

    errors.add(:value, :invalid)
  end
end
