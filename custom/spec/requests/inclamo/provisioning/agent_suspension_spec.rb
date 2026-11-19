# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# A suspended account has no agent (design D8, task 3.9): the removal notice
# disconnects it, and restoring the account does not connect it again.
RSpec.describe 'App agent connection: suspension and restoration', type: :request do
  include_context 'with the store app and the AI service'

  let(:account) { provisioned.account }
  let(:storefront) { provisioned.storefront_inbox }
  let(:record) { connection_of(account) }

  before do
    provision
    stub_ai_registration
    connect_agent
    expect(response).to have_http_status(:created)
  end

  it 'ends with the account suspended, no bot, and the AI service told' do
    removal = stub_ai_removal
    pending = create(:conversation, account: account, inbox: storefront.reload)
    token = AgentBot.find(record.agent_bot_id).access_token.token

    remove_app

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('contract' => 1, 'state' => 'suspended')
    expect(account.reload).to be_suspended
    expect(agent_bots_of(account)).to be_empty
    expect(AccessToken.find_by(token: token)).to be_nil
    expect(pending.reload.status).to eq('open')
    expect(record.reload).to have_attributes(state: 'disconnected', removal_error: nil)
    expect(removal.with(headers: { 'Authorization' => "Bearer #{token}" })).to have_been_requested.once
  end

  it 'suspends all the same when the AI service cannot be reached, and notes it' do
    stub_request(:delete, "#{AiServiceStubs::AI_SERVICE_URL}/connections/conn-1").to_raise(Errno::ECONNREFUSED)

    remove_app

    expect(response).to have_http_status(:ok)
    expect(account.reload).to be_suspended
    expect(agent_bots_of(account)).to be_empty
    expect(record.reload).to have_attributes(state: 'disconnected', removal_error: 'not_answered')
  end

  it 'leaves the restored account disconnected until the app asks again' do
    stub_ai_removal
    remove_app

    provision
    expect(response.parsed_body['outcome']).to eq('restored')

    expect(account.reload).to be_active
    expect(agent_bots_of(account)).to be_empty
    expect(record.reload.state).to eq('disconnected')
    expect(create(:conversation, account: account, inbox: storefront.reload).status).to eq('open')
    ask_agent_status
    expect(response.parsed_body).to include('state' => 'disconnected', 'inbox_ids' => [])

    connect_agent
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('outcome' => 'connected', 'inbox_ids' => [storefront.id])
  end

  it 'answers a repeated notice as before, with nothing more told to the AI service' do
    removal = stub_ai_removal
    remove_app

    remove_app

    expect(response.parsed_body).to eq('contract' => 1, 'state' => 'suspended')
    expect(removal).to have_been_requested.once
  end
end

RSpec.describe Inclamo::Provisioning::AgentConnection, '.suspending' do
  include AiServiceStubs

  let(:account) { create(:account) }
  let(:website) { create(:inbox, account: account) }

  before do
    resolve_ai_service_publicly
    stub_ai_removal
  end

  it 'disconnects before the suspension, and does nothing for an account that is not connected' do
    record = connect_ai_agent(account, [website])
    states = []

    described_class.suspending(account) { states << record.reload.state }

    expect(states).to eq(['disconnected'])
    described_class.suspending(account) { states << :again }
    expect(states).to eq(['disconnected', :again])
  end

  it 'disconnects once more after the suspension a connection that was made meanwhile' do
    result = described_class.suspending(account) do
      connect_ai_agent(account, [website])
      'suspended'
    end

    expect(result).to eq('suspended')
    expect(Inclamo::AiConnection.active_for(account.id)).to be_nil
    expect(AgentBot.where(account_id: account.id)).to be_empty
  end

  it 'waits for a connection under way to end, and gives up after a while' do
    connect_ai_agent(account, [website])
    stub_const("#{described_class}::SUSPENSION_WAIT", 0.5)
    Redis::Alfred.set("inclamo:ai:#{account.id}:connection", 'held', nx: true, ex: 60)

    expect { described_class.suspending(account) { nil } }.to raise_error(Inclamo::Ai::Error::Busy)

    Redis::Alfred.delete("inclamo:ai:#{account.id}:connection")
    expect { described_class.suspending(account) { nil } }.not_to raise_error
    expect(Inclamo::AiConnection.active_for(account.id)).to be_nil
  end
end
