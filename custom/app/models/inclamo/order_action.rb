# frozen_string_literal: true

# The record of one attempt to act on an order: who, in which conversation,
# what, in which macro if any, and how it ended. See
# Inclamo::Shopify::OrderActionRunner.
class Inclamo::OrderAction < ApplicationRecord
  ACTIONS = %w[cancel refund address replacement new_order].freeze
  # Actions that are not about an existing order: their record has no order id.
  ORDER_LESS = %w[new_order].freeze
  OUTCOMES = %w[pending running accepted refused unknown].freeze

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :action_id, presence: true, uniqueness: { scope: :account_id }, format: { with: /\A[A-Za-z0-9-]{8,64}\z/ }
  validates :order_id, presence: true, unless: :order_less?

  # What a new order's record tells the dialog: the draft, its total, its
  # payment link and how the link reached the customer.
  NEW_ORDER_RESULT = %w[draft_id draft_name total invoice_url invoice_sent delivery].freeze

  scope :unsettled, -> { where(outcome: %w[pending running unknown]) }

  def self.order_less?(action)
    ORDER_LESS.include?(action.to_s)
  end

  def order_less?
    self.class.order_less?(action)
  end

  def settled?
    %w[accepted refused].include?(outcome)
  end

  def as_json(*)
    {
      action_id: action_id, action: action, order_id: order_id, order_number: order_number, outcome: outcome,
      refusal: refusal, store_message: store_message, result: progress.slice('new_order_number', 'new_order_id', 'refunded', *NEW_ORDER_RESULT),
      macro_id: macro_id, created_at: created_at, completed_at: completed_at
    }
  end
end
