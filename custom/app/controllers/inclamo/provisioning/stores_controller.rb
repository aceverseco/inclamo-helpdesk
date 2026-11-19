# frozen_string_literal: true

# The three calls of the store app (docs/app-provisioning.md). They sit outside
# any account and any user session: the only thing that opens them is the
# signature made with the secret the operator shares with the app.
class Inclamo::Provisioning::StoresController < ActionController::API
  PENDING_WAIT = 5.0
  UNAUTHORIZED = { error: 'unauthorized' }.freeze

  before_action :authorize
  around_action :answer_once

  # PUT: the store has an account. Create it, find it or restore it.
  def update
    result = Inclamo::Provisioning::Provision.new(Inclamo::Provisioning::Payload.new(request.raw_post, @verdict.shop_domain)).call
    record(result.outcome)
    body = account_body(result.row, result.account).merge(outcome: result.outcome)
    body[:password_setup_url] = result.password_setup_url if result.password_setup_url
    render json: body, status: result.outcome == 'created' ? :created : :ok
  rescue Inclamo::Provisioning::Payload::Invalid => e
    record('refused')
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  end

  # GET: what the store has. Never users, conversations or shopper data.
  def show
    row = Inclamo::ProvisionedAccount.for_store(@verdict.shop_domain)
    return render json: { error: 'no_account' }, status: :not_found unless row&.account

    render json: account_body(row, row.account)
  end

  # POST removal: the app was removed from the store.
  def removal
    state = Inclamo::Provisioning::Removal.new(@verdict.shop_domain).call
    record(state)
    render json: { contract: Inclamo::Provisioning::CONTRACT, state: state }
  end

  private

  def authorize
    @verdict = Inclamo::Provisioning::Gate.check(request.env)
    refuse unless @verdict.passed?
  end

  # A request id is answered once: its repetition gets the stored answer, and
  # nothing is done a second time.
  def answer_once
    store = Inclamo::Provisioning::RequestStore
    held = store.reserve(@verdict.request_id, @verdict.digest)
    held = wait_for_answer if held == :pending
    return refuse if held == :conflict
    return replay(held) unless held == :reserved

    begin
      yield
      store.keep(@verdict.request_id, @verdict.digest, status: response.status, body: response.body, outcome: @outcome)
    rescue StandardError
      store.release(@verdict.request_id)
      raise
    end
  end

  # The same request is being answered by another process right now.
  def wait_for_answer
    store = Inclamo::Provisioning::RequestStore
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PENDING_WAIT
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      answer = store.answer_for(@verdict.request_id, @verdict.digest)
      return answer if answer

      sleep 0.1
    end
    :pending
  end

  def replay(answer)
    if answer == :pending
      response.headers['Retry-After'] = '1'
      return render json: { error: 'in_progress' }, status: :service_unavailable
    end

    record(answer.outcome) if answer.outcome
    render json: answer.body, status: answer.status
  end

  def refuse
    record('refused')
    render json: UNAUTHORIZED, status: :unauthorized
  end

  def record(outcome)
    @outcome = outcome
    Inclamo::ProvisioningEvent.record(outcome: outcome, shop_domain: @verdict.shop_domain, request_id: @verdict.request_id)
  end

  def account_body(row, account)
    {
      contract: Inclamo::Provisioning::CONTRACT,
      account_id: account.id,
      helpdesk_url: Inclamo::Provisioning.helpdesk_url,
      state: row.suspended? || account.suspended? ? 'suspended' : 'active',
      created_at: account.created_at.utc.iso8601
    }
  end
end
