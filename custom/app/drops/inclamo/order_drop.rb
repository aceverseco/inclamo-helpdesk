# frozen_string_literal: true

# `{{order.*}}` in an outgoing message: the facts of the order the conversation
# is about — the order tied to it, or, when none is tied, the latest order of
# the customer its contact is matched to. The order is read from the store on
# first use, so a message without order variables costs no store call. The
# store never holds a message back: the reads share one time limit, and when
# they fail a tied order's variables take the values last written on the
# conversation; without a tied order they are empty.
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
    @values ||= read
  end

  def attributes
    @conversation&.custom_attributes.to_h
  end

  def order_id
    attributes[Inclamo::Shopify::ConversationOrder::ID_KEY]
  end

  def read
    return {} if @conversation.nil?

    @record = Inclamo::ShopifyConnection.find_by(account_id: @conversation.account_id)
    return {} unless @record

    @deadline = now + TIME_LIMIT
    node = order_id.present? ? reader.order(order_id) : latest_order
    node ? Inclamo::Shopify::OrderVariables.new(node).to_h : {}
  rescue StandardError => e
    Rails.logger.info("[inclamo] order variables of conversation #{@conversation.id} not read from the store: #{e.class.name}")
    order_id.present? ? last_known : {}
  end

  # The newest order of the customer the panel shows for this conversation's
  # contact; nil when the contact matches no customer, or the customer has none.
  def latest_order
    match = Inclamo::Shopify::CustomerMatcher.new(reader, @conversation.contact, limited: @record.customer_data_limited?).call
    return unless match.state == 'matched'

    customer = reader.customer_with_orders(match.customer_id)
    Array(customer&.dig('orders', 'nodes')).first
  end

  # A reader with what is left of the time limit: every read of this message shares it.
  def reader
    Inclamo::Shopify::OrderReader.new(@record, time_limit: @deadline - now)
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def last_known
    LAST_KNOWN.to_h do |name, key|
      value = attributes[key].to_s
      [name, STATUSES.include?(name) ? Inclamo::Shopify::StatusWords.for(value) : value]
    end
  end
end
