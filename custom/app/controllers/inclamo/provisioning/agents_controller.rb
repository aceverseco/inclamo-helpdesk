# frozen_string_literal: true

# The store app's three calls about a store's AI agent
# (docs/app-agent-connection.md): connect, how the connection is doing,
# disconnect. They are opened by the same signature, answer a request id once
# and are recorded as the store app's other calls, which is what this
# controller takes from the one it extends. No answer carries the bot's token
# or secret, the pairing token, or anything of a conversation.
class Inclamo::Provisioning::AgentsController < Inclamo::Provisioning::StoresController
  RETRY_AFTER = 5

  # PUT: the store's account is connected to the agent.
  def update
    payload = Inclamo::Provisioning::AgentPayload.new(request.raw_post)
    result = service.connect(payload)
    record("agent_#{result.outcome}")
    render json: connection_body(result.record).merge(outcome: result.outcome), status: result.outcome == 'connected' ? :created : :ok
  rescue Inclamo::Provisioning::Payload::Invalid => e
    record('agent_refused')
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  rescue Inclamo::Provisioning::AgentConnection::Refused => e
    record(e.code == 'agent_not_answered' ? 'agent_not_answered' : 'agent_refused')
    refuse_with(e)
  end

  # GET: how the connection is doing.
  def show
    connection = service.status
    record('agent_status')
    render json: status_body(connection)
  rescue Inclamo::Provisioning::AgentConnection::Refused => e
    record('agent_status')
    refuse_with(e)
  end

  # DELETE: the agent is disconnected; done already is done.
  def destroy
    state, told = service.disconnect
    record('agent_disconnected')
    render json: { contract: Inclamo::Provisioning::CONTRACT, state: state, ai_service_told: told }
  rescue Inclamo::Provisioning::AgentConnection::Refused => e
    record('agent_refused')
    refuse_with(e)
  end

  private

  def service
    Inclamo::Provisioning::AgentConnection.new(@verdict.shop_domain)
  end

  def refuse_with(error)
    response.headers['Retry-After'] = RETRY_AFTER.to_s if error.code == 'busy'
    render json: { error: error.code }.merge(error.details), status: error.status
  end

  def connection_body(connection)
    {
      contract: Inclamo::Provisioning::CONTRACT,
      state: connection.state,
      inbox_ids: Inclamo::Provisioning::AgentConnection.answering_inbox_ids(connection),
      phone_inbox_id: connection.phone_inbox_id,
      connected_at: time(connection.connected_at)
    }
  end

  # A disconnected connection keeps when and how it was made and its last
  # deliveries; it answers in no inbox. One that never was has every field empty.
  def status_body(connection)
    {
      contract: Inclamo::Provisioning::CONTRACT,
      state: connection&.state || 'never_connected',
      connected_via: connection&.connected_via,
      inbox_ids: Inclamo::Provisioning::AgentConnection.answering_inbox_ids(connection),
      phone_inbox_id: connection&.phone_inbox_id,
      connected_at: time(connection&.connected_at),
      last_reply_at: time(connection&.last_reply_at),
      last_delivered_at: time(connection&.last_delivered_at),
      last_failed_at: time(connection&.last_failed_at),
      last_error: connection&.last_error
    }
  end

  def time(value)
    value&.utc&.iso8601
  end
end
