# frozen_string_literal: true

# The store app's request to erase a store's account (docs/app-store-erasure.md
# §3), which it sends when Shopify asks to erase the store. It is opened by the
# same signature, answers a request id once and is recorded as the store app's
# other calls, which is what this controller takes from the one it extends.
# The request schedules the erasure; it destroys nothing itself.
class Inclamo::Provisioning::ErasuresController < Inclamo::Provisioning::StoresController
  # POST erasure: scheduled, under way, done, or nothing to erase.
  def create
    Inclamo::Provisioning::ErasurePayload.new(request.raw_post)
    answer = Inclamo::Erasure::Schedule.new(@verdict.shop_domain).call
    record(answer.outcome)
    render json: answer.body
  rescue Inclamo::Provisioning::Payload::Invalid => e
    record('refused')
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  rescue Inclamo::Erasure::Schedule::AccountActive
    record('refused')
    render json: { error: 'account_active' }, status: :conflict
  end
end
