# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# The agent's calls under the provisioning limits: the `PUT` counts with the
# account's and the storefront chat's `PUT`s of the same store and of the
# installation, the `GET` with the other status calls, and the `DELETE` is
# not limited.
RSpec.describe 'App agent connection: limits', type: :request do
  include_context 'with the store app and the AI service'

  # As in limits_spec.rb: Rack::Attack on, counting in memory, an outside address.
  let(:outside) { { 'REMOTE_ADDR' => '203.0.113.9' } }

  around do |example|
    enabled = Rack::Attack.enabled
    cache = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    with_modified_env(INCLAMO_APP_PROVISIONING_PUT_LIMIT: '30', INCLAMO_APP_PROVISIONING_STORE_LIMIT: '3',
                      INCLAMO_APP_PROVISIONING_GET_LIMIT: '3') { example.run }
  ensure
    Rack::Attack.cache.store = cache
    Rack::Attack.enabled = enabled
  end

  def expect_limited
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'rate_limited')
    expect(response.headers['Retry-After']).to match(/\A\d+\z/)
  end

  it "counts the agent's PUT with the store's other PUTs, and creates nothing over the limit" do
    registration = stub_ai_registration
    provision(headers: outside)
    ask_for_chat(headers: outside)
    expect(response).to have_http_status(:ok)

    connect_agent(headers: outside)
    expect(response).to have_http_status(:created)

    connect_agent(headers: outside)
    expect_limited
    expect(registration).to have_been_requested.once
    expect(Inclamo::ProvisioningEvent.order(:id).last).to have_attributes(outcome: 'limited', shop_domain: ProvisioningRequests::STORE)

    provision('second-store.myshopify.com', headers: outside)
    expect(response).to have_http_status(:created)
  end

  it 'refuses a connection over the limit before anything is made' do
    registration = stub_ai_registration
    provision(headers: outside)
    2.times { ask_for_chat(headers: outside) }
    account = provisioned.account

    expect { connect_agent(headers: outside) }.not_to(change { made_for_agent(account) })

    expect_limited
    expect(registration).not_to have_been_requested
  end

  it "counts the agent's status call with the other status calls of the installation" do
    provision(headers: outside)
    ask_status(headers: outside)
    ask_chat_status(headers: outside)
    ask_agent_status(headers: outside)
    expect(response).to have_http_status(:ok)

    ask_agent_status(headers: outside)
    expect_limited
    ask_status(headers: outside)
    expect_limited
  end

  it "does not count a replay of the agent's PUT, and counts one refused for its body" do
    registration = stub_ai_registration
    provision(headers: outside)
    request_id = SecureRandom.uuid
    connect_agent(headers: outside, request_id: request_id)
    expect(response).to have_http_status(:created)

    2.times do
      connect_agent(headers: outside, request_id: request_id)
      expect(response).to have_http_status(:created)
    end
    connect_agent(headers: outside, with: { service_url: 'https://attacker.example.net' })
    expect(response).to have_http_status(:unprocessable_entity)

    connect_agent(headers: outside)
    expect_limited
    expect(registration).to have_been_requested.once
  end

  it 'does not limit the disconnection' do
    stub_ai_registration
    stub_ai_removal
    provision(headers: outside)
    connect_agent(headers: outside)
    ask_for_chat(headers: outside)
    3.times { ask_agent_status(headers: outside) }

    disconnect_agent(headers: outside)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']).to eq('disconnected')
    5.times do
      disconnect_agent(headers: outside)
      expect(response).to have_http_status(:ok)
    end
  end
end
