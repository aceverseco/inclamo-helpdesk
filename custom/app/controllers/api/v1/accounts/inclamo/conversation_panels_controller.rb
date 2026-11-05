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

  private

  def panel
    ::Inclamo::Shopify::Panel.new(account: Current.account, conversation: @conversation, account_user: Current.account_user)
  end

  def connection
    ::Inclamo::ShopifyConnection.working.find_by(account_id: Current.account.id)
  end
end
