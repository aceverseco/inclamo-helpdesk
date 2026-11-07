# frozen_string_literal: true

# The store's catalogue, searched from a conversation by title or SKU. Shared
# by every dialog that picks a product. Open to every member who may see the
# conversation; the connected app needs read_products.
class Api::V1::Accounts::Inclamo::ProductsController < Api::V1::Accounts::Conversations::BaseController
  include Api::V1::Accounts::Inclamo::StoreAnswers

  # GET .../products?query=...&after=...
  def index
    connection = ::Inclamo::ShopifyConnection.find_by(account_id: Current.account.id)
    return render json: { error: 'not_connected' }, status: :not_found unless connection
    return render json: { error: 'connection_broken' }, status: :conflict if connection.broken?

    search = ::Inclamo::Shopify::ProductSearch.new(connection)
    missing = search.missing_scopes
    return render json: { error: 'missing_scope', missing_scopes: missing }, status: :unprocessable_entity if missing.any?

    answer_from_store { search.call(params[:query], after: params[:after]) }
  end
end
