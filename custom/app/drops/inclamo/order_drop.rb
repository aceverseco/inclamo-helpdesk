# frozen_string_literal: true

# `{{order.*}}` in an outgoing message: the facts of the order the conversation
# is about. The order is read from the store on first use, so a message without
# order variables costs no store call. The store never holds a message back:
# the read has a time limit, and when it fails the variables take the values
# last written on the conversation.
class Inclamo::OrderDrop < Liquid::Drop
  TIME_LIMIT = 3 # seconds
  # variable => the conversation attribute that keeps its last known value
  LAST_KNOWN = {
    'number' => 'shopify_order_number',
    'payment_status' => 'shopify_order_payment_status',
    'fulfillment_status' => 'shopify_order_fulfillment_status',
    'tracking_number' => 'shopify_order_tracking_number',
    'tracking_link' => 'shopify_order_tracking_link'
  }.freeze
  STATUSES = %w[payment_status fulfillment_status].freeze

  def initialize(conversation)
    super()
    @conversation = conversation
  end

  Inclamo::Shopify::OrderVariables::NAMES.each do |name|
    define_method(name) { values[name].presence }
  end

  private

  def values
    @values ||= order_id.blank? ? {} : read
  end

  def attributes
    @conversation&.custom_attributes.to_h
  end

  def order_id
    attributes[Inclamo::Shopify::ConversationOrder::ID_KEY]
  end

  def read
    record = Inclamo::ShopifyConnection.find_by(account_id: @conversation.account_id)
    return {} unless record

    node = Inclamo::Shopify::OrderReader.new(record, time_limit: TIME_LIMIT).order(order_id)
    node ? Inclamo::Shopify::OrderVariables.new(node).to_h : {}
  rescue StandardError => e
    Rails.logger.info("[inclamo] order variables of conversation #{@conversation.id} taken from its attributes: #{e.class.name}")
    last_known
  end

  def last_known
    LAST_KNOWN.to_h do |name, key|
      value = attributes[key].to_s
      [name, STATUSES.include?(name) ? Inclamo::Shopify::StatusWords.for(value) : value]
    end
  end
end
