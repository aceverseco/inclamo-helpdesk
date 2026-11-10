# frozen_string_literal: true

# How the overlay's controllers answer a read that the agent's rights, the
# connection or the store did not allow. The refusal is named as order
# actions name it (OrderActionRunner.refusal_for): a store that could not be
# reached is a bad gateway, an agent without the role is forbidden, anything
# else cannot be processed.
module Api::V1::Accounts::Inclamo::StoreAnswers
  private

  # Renders what the block returns, or why there is nothing to render.
  def answer_from_store
    render json: yield
  rescue ::Inclamo::Shopify::Actions::Refused, ::Inclamo::Shopify::Error => e
    refused = ::Inclamo::Shopify::OrderActionRunner.refusal_for(e)
    status = if refused[:reason] then :bad_gateway
             elsif refused[:refusal] == 'not_allowed' then :forbidden
             else :unprocessable_entity
             end
    render json: { error: refused[:refusal], message: refused[:message], reason: refused[:reason] }.compact, status: status
  end
end
