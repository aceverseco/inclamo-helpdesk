# frozen_string_literal: true

# The "Orders" section of one conversation: what it shows, the customer an
# agent chose for the contact, and lookup of an order by its number. Open to
# every member who may see the conversation.
class Api::V1::Accounts::Inclamo::ConversationPanelsController < Api::V1::Accounts::Conversations::BaseController
  def show
    render json: panel.as_json(after: params[:after].presence)
  end

  # Keeps a customer of the store for this conversation's contact.
  def choose_customer
    record = connection
    return head :not_found unless record

    customer = ::Inclamo::Shopify::OrderReader.new(record).customer_with_orders(params[:customer_id].to_s)
    return render json: { error: 'unknown_customer' }, status: :unprocessable_entity unless customer

    ::Inclamo::Shopify::CustomerMatcher.remember!(@conversation.contact, customer['id'])
    render json: panel.as_json
  rescue ::Inclamo::Shopify::Error => e
    render json: { error: 'store_unreachable', reason: e.class.name.demodulize.underscore }, status: :bad_gateway
  end

  def forget_customer
    ::Inclamo::Shopify::CustomerMatcher.remember!(@conversation.contact, nil)
    render json: panel.as_json
  end

  # GET .../lookup?number=1042
  def lookup
    record = connection
    return head :not_found unless record

    node = ::Inclamo::Shopify::OrderReader.new(record).order_by_number(params[:number])
    return render json: { found: false } unless node

    render json: { found: true, order: panel.present_order(node) }
  rescue ::Inclamo::Shopify::Error => e
    render json: { error: 'store_unreachable', reason: e.class.name.demodulize.underscore }, status: :bad_gateway
  end

  # GET .../marks?order_id=... or ?customer_id=...  The tags and note as the
  # store holds them now, past the panel's cache: the note editor starts from it.
  def marks
    record = connection
    return head :not_found unless record

    reader = ::Inclamo::Shopify::OrderReader.new(record)
    if params[:customer_id].present?
      return render json: { error: 'customer_data_hidden' }, status: :unprocessable_entity if record.customer_data_limited?

      node = reader.customer_marks(params[:customer_id].to_s)
    else
      node = reader.order_marks(params[:order_id].to_s)
    end
    return render json: { error: 'unknown' }, status: :unprocessable_entity unless node

    render json: { id: node['id'], tags: Array(node['tags']), note: node['note'].presence }
  rescue ::Inclamo::Shopify::Error => e
    render json: { error: 'store_unreachable', reason: e.class.name.demodulize.underscore }, status: :bad_gateway
  end

  # Marks the order this conversation is about. params[:order_id] is the id
  # the panel shows for the order.
  def mark_order
    record = connection
    return head :not_found unless record

    node = ::Inclamo::Shopify::OrderReader.new(record).order(params[:order_id].to_s)
    return render json: { error: 'unknown_order' }, status: :unprocessable_entity unless node

    ::Inclamo::Shopify::ConversationOrder.new(@conversation).mark!(node)
    render json: panel.as_json
  rescue ::Inclamo::Shopify::Error => e
    render json: { error: 'store_unreachable', reason: e.class.name.demodulize.underscore }, status: :bad_gateway
  end

  def clear_order
    ::Inclamo::Shopify::ConversationOrder.new(@conversation).clear!
    render json: panel.as_json
  end

  private

  def panel
    ::Inclamo::Shopify::Panel.new(account: Current.account, conversation: @conversation, account_user: Current.account_user)
  end

  def connection
    ::Inclamo::ShopifyConnection.working.find_by(account_id: Current.account.id)
  end
end
