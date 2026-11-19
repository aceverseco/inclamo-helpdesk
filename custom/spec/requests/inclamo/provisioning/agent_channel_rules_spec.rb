# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# The provisioning channel's own rules, as the agent's three calls meet them:
# the request id inside the signed text, a reused id, a retry while the first
# request is still answered, the header on every answer, and the shared
# limits' defaults. They are kept by the channel (Gate, RequestStore, Limits,
# StoresController, InclamoProvisioningHeader), not by the agent's code; the
# agent's addresses join it through Provisioning::ADDRESSES.
RSpec.describe 'App agent connection: the rules of the provisioning channel', type: :request do
  include_context 'with the store app and the AI service'

  let(:path) { provisioning_path(ProvisioningRequests::STORE, '/agent') }

  before { provision }

  def signed_headers(text, timestamp, request_id)
    {
      'CONTENT_TYPE' => 'application/json', 'X-Inclamo-Timestamp' => timestamp.to_s, 'X-Inclamo-Request-Id' => request_id,
      'X-Inclamo-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', ProvisioningRequests::SECRET, text)}"
    }
  end

  describe 'the signed text holds the request id' do
    it 'accepts <timestamp>.<request id>.<METHOD>.<path>.<raw body>' do
      timestamp = Time.now.to_i
      request_id = SecureRandom.uuid

      get path, headers: signed_headers("#{timestamp}.#{request_id}.GET.#{path}.", timestamp, request_id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('never_connected')
    end

    it 'refuses the text without the request id' do
      timestamp = Time.now.to_i

      get path, headers: signed_headers("#{timestamp}.GET.#{path}.", timestamp, SecureRandom.uuid)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'answers a request id seen with another method as reused' do
    stub_ai_registration
    request_id = SecureRandom.uuid
    ask_agent_status(request_id: request_id)
    expect(response).to have_http_status(:ok)

    disconnect_agent(request_id: request_id)

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'request_id_reused')
  end

  it 'answers a retry of a connection still being answered as in progress, with the time to try again' do
    stub_const('Inclamo::Provisioning::StoresController::PENDING_WAIT', 0.2)
    request_id = SecureRandom.uuid
    body = JSON.generate(agent_body)
    digest = Inclamo::Provisioning::RequestStore.digest(method: 'PUT', path: path, body: body)
    expect(Inclamo::Provisioning::RequestStore.reserve(request_id, digest)).to eq(:reserved)

    connect_agent(request_id: request_id, body: body)

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'in_progress')
    expect(response.headers['Retry-After']).to eq(Inclamo::Provisioning::StoresController::RETRY_PENDING.to_s)
    expect(connection_of(provisioned.account)).to be_nil
  end

  it 'marks every answer of the agent calls as the provisioning channel' do
    stub_ai_registration
    stub_ai_removal
    calls = {
      'connected' => -> { connect_agent }, 'existed' => -> { connect_agent }, 'status' => -> { ask_agent_status },
      'disconnected' => -> { disconnect_agent },
      'unauthorized' => -> { connect_agent(secret: 'another-secret-0123456789abcdef-0123456789abcdef') },
      'no_account' => -> { connect_agent('unknown-store.myshopify.com') }, 'contract_unsupported' => -> { connect_agent(with: { contract: 9 }) }
    }

    marks = calls.transform_values { |call| call.call.headers['X-Inclamo-Provisioning'] }

    expect(marks).to eq(calls.keys.index_with('1'))
  end

  it 'counts the agent\'s PUT with the store\'s PUTs, its GET with the status calls, and its DELETE nowhere' do
    expect(Inclamo::Provisioning::ADDRESSES.fetch('/agent')).to eq('PUT' => :put, 'GET' => :get, 'DELETE' => nil)
  end

  it "has the shared limits' defaults: 15 PUTs an hour per store and 120 for the installation" do
    with_modified_env INCLAMO_APP_PROVISIONING_PUT_LIMIT: nil, INCLAMO_APP_PROVISIONING_STORE_LIMIT: nil, INCLAMO_APP_PROVISIONING_GET_LIMIT: nil do
      expect(%i[put store get].map { |name| Inclamo::Provisioning.limit(name) }).to eq([120, 15, 300])
    end
  end
end
