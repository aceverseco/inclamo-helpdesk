# frozen_string_literal: true

# The record of one attempt to act on an order: who, in which conversation,
# what, and how it ended. See Inclamo::Shopify::OrderActionRunner.
class Inclamo::OrderAction < ApplicationRecord
  ACTIONS = %w[cancel refund address replacement].freeze
  OUTCOMES = %w[pending running accepted refused unknown].freeze

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :action_id, presence: true, uniqueness: { scope: :account_id }, format: { with: /\A[A-Za-z0-9-]{8,64}\z/ }
  validates :order_id, presence: true

  scope :unsettled, -> { where(outcome: %w[pending running unknown]) }

  def settled?
    %w[accepted refused].include?(outcome)
  end

  def as_json(*)
    {
      action_id: action_id, action: action, order_id: order_id, order_number: order_number, outcome: outcome,
      refusal: refusal, store_message: store_message, result: progress.slice('new_order_number', 'new_order_id', 'refunded'),
      created_at: created_at, completed_at: completed_at
    }
  end
end
