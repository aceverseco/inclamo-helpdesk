# frozen_string_literal: true

# The record of one attempt to act on an order: who, in which conversation,
# what, and how it ended. See Inclamo::Shopify::OrderActionRunner.
class Inclamo::OrderAction < ApplicationRecord
  ACTIONS = %w[cancel refund address replacement order_tags order_note customer_tags customer_note].freeze
  # Actions on the customer rather than on an order: they carry a customer id.
  CUSTOMER_ACTIONS = %w[customer_tags customer_note].freeze
  OUTCOMES = %w[pending running accepted refused unknown].freeze

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :action_id, presence: true, uniqueness: { scope: :account_id }, format: { with: /\A[A-Za-z0-9-]{8,64}\z/ }
  validates :order_id, presence: true, unless: :customer_action?
  validates :customer_id, presence: true, if: :customer_action?

  scope :unsettled, -> { where(outcome: %w[pending running unknown]) }

  def self.customer_action?(action)
    CUSTOMER_ACTIONS.include?(action.to_s)
  end

  def customer_action?
    self.class.customer_action?(action)
  end

  def settled?
    %w[accepted refused].include?(outcome)
  end

  def as_json(*)
    {
      action_id: action_id, action: action, order_id: order_id, customer_id: customer_id, order_number: order_number, outcome: outcome,
      refusal: refusal, store_message: store_message, result: progress.slice('new_order_number', 'new_order_id', 'refunded'),
      created_at: created_at, completed_at: completed_at
    }
  end
end
