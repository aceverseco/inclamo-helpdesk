# frozen_string_literal: true

# The store app's request to let a Shopify staff member into the store's
# account without a helpdesk password (docs/app-admin-entry.md §1). It is
# opened by the same signature as the store app's other calls and is recorded
# as they are, with outcomes of its own and the user it found.
#
# Unlike the other calls, a request id is used once: a repetition is refused
# as reused, whatever its body, and nothing of the answer is kept. A stored
# answer would hand the same one-time address to whoever replays the request.
class Inclamo::Provisioning::EntriesController < Inclamo::Provisioning::StoresController
  skip_around_action :answer_once
  before_action :take_request_id

  # POST entry: a one-time address for the person, or why not.
  def create
    result = Inclamo::Provisioning::Entry.new(@verdict.shop_domain, request.raw_post).call
    record(result.outcome, result.user_id)
    render json: result.body, status: result.status
  rescue Inclamo::Provisioning::Payload::Invalid => e
    record('entry_refused')
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  end

  private

  # The id joins the ids of every provisioning call for ten minutes, marked as
  # this call's, with no answer.
  def take_request_id
    store = Inclamo::Provisioning::RequestStore
    taken = Redis::Alfred.set(store.key(@verdict.request_id), { digest: @verdict.digest, single_use: true }.to_json,
                              nx: true, ex: store::KEEP)
    reused unless taken
  end

  def refuse
    record('entry_refused')
    render json: UNAUTHORIZED, status: :unauthorized
  end

  def reused
    record('entry_refused')
    render json: { error: 'request_id_reused' }, status: :conflict
  end

  def record(outcome, user_id = nil)
    Inclamo::ProvisioningEvent.record(outcome: outcome, shop_domain: @verdict.shop_domain, request_id: @verdict.request_id,
                                      user_id: user_id)
  end
end
