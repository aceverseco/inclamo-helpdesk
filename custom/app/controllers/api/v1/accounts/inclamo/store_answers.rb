# frozen_string_literal: true

# How the overlay's controllers answer a read that the agent's rights, the
# connection or the store did not allow: one mapping of the overlay's errors
# to HTTP answers.
module Api::V1::Accounts::Inclamo::StoreAnswers
  private

  # Renders what the block returns, or why there is nothing to render.
  def answer_from_store
    render json: yield
  rescue ::Inclamo::Shopify::Actions::Refused => e
    render json: { error: e.code, message: (e.message unless e.message == e.code) }, status: e.code == 'not_allowed' ? :forbidden : :unprocessable_entity
  rescue ::Inclamo::Shopify::Error::ConnectionBroken, ::Inclamo::Shopify::Error::Unauthorized
    render json: { error: 'connection_broken' }, status: :conflict
  rescue ::Inclamo::Shopify::Error::QueryError => e
    render json: { error: 'store_refused', message: e.message.first(500) }, status: :unprocessable_entity
  rescue ::Inclamo::Shopify::Error => e
    render json: { error: 'store_unreachable', reason: e.class.name.demodulize.underscore }, status: :bad_gateway
  end
end
