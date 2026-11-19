# frozen_string_literal: true

# The store app's three calls about one shopper of a store
# (docs/app-store-erasure.md §4–§6): Shopify asked to erase the shopper, or to
# give the store owner the shopper's data, and how many such requests of the
# store wait. They are opened by the same signature, answer a request id once
# and are recorded as the store app's other calls, which is what this
# controller takes from the one it extends. No answer holds the shopper's
# email, phone or name, a message, a hold's reason or an administrator, so
# the answer kept for a repeated request id holds none either. Nothing here
# deletes anything.
class Inclamo::Provisioning::ShopperRequestsController < Inclamo::Provisioning::StoresController
  # POST shoppers/erasure: a ticket to erase one shopper.
  def erasure
    answer_request('shopper_erasure')
  end

  # POST shoppers/data-request: a ticket to give the store owner one shopper's data.
  def data_request
    answer_request('shopper_data_request')
  end

  # GET shoppers/requests: numbers only.
  def counts
    counts = Inclamo::Erasure::ShopperCounts.call(@verdict.shop_domain)
    return render json: { error: 'no_account' }, status: :not_found unless counts

    render json: counts
  end

  private

  def answer_request(kind)
    payload = Inclamo::Provisioning::ShopperPayload.new(request.raw_post)
    answer = Inclamo::Erasure::ShopperRequest.new(@verdict.shop_domain, kind, payload).call
    record(answer.outcome)
    render json: answer.body
  rescue Inclamo::Provisioning::Payload::Invalid => e
    record('refused')
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  end
end
