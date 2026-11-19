# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# Who may reach a store's agent through the store app's calls (design D1,
# task 3.1 and 3.2): the routes exist only with the secret, every call is
# signed for its own method and path, and only a provisioned, active account
# is reached.
RSpec.describe 'App agent connection: who is asking and for which account', type: :request do
  include_context 'with the store app and the AI service'

  let(:other_secret) { 'another-secret-0123456789abcdef-0123456789abcdef' }

  describe 'an installation without provisioning' do
    it 'answers the three calls as any unknown address' do
      with_modified_env INCLAMO_APP_PROVISIONING_SECRET: nil do
        Rails.application.reload_routes!
        registration = stub_ai_registration

        expect(connect_agent).to have_http_status(:not_found)
        expect(ask_agent_status).to have_http_status(:not_found)
        expect(disconnect_agent).to have_http_status(:not_found)
        expect(response.body).not_to include('no_account')
        expect(registration).not_to have_been_requested
      end
    end
  end

  describe 'a provisioned, active account' do
    before { provision }

    let(:account) { provisioned.account }

    it 'is not connected by a request signed with another secret' do
      registration = stub_ai_registration

      expect { connect_agent(secret: other_secret) }.not_to(change { made_for_agent(account) })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'unauthorized')
      expect(connection_of(account)).to be_nil
      expect(registration).not_to have_been_requested
    end

    it 'refuses a stale request and one without a request id' do
      stub_ai_registration

      connect_agent(timestamp: 10.minutes.ago.to_i)
      expect(response).to have_http_status(:unauthorized)
      connect_agent(request_id: 'not-a-uuid')
      expect(response).to have_http_status(:unauthorized)
      expect(connection_of(account)).to be_nil
    end

    it 'does not take a status request replayed as a disconnection' do
      stub_ai_registration
      connect_agent
      expect(response).to have_http_status(:created)
      removal = stub_ai_removal

      disconnect_agent(signed_as: ['GET', provisioning_path(ProvisioningRequests::STORE, '/agent')])

      expect(response).to have_http_status(:unauthorized)
      expect(connection_of(account)).to be_active
      expect(removal).not_to have_been_requested
    end

    it 'does not take a disconnection signed for the account address, or the connection signed as its status' do
      stub_ai_registration

      connect_agent(signed_as: ['GET', provisioning_path(ProvisioningRequests::STORE, '/agent')])
      expect(response).to have_http_status(:unauthorized)
      disconnect_agent(signed_as: ['DELETE', provisioning_path])
      expect(response).to have_http_status(:unauthorized)
      expect(connection_of(account)).to be_nil
    end
  end

  describe 'a store without an account' do
    it 'is refused on each call, and nothing is created or asked' do
      registration = stub_ai_registration

      expect { connect_agent('unknown-store.myshopify.com') }
        .to not_change(AgentBot, :count).and not_change(Inbox, :count).and not_change(Inclamo::AiConnection, :count)
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')

      expect(ask_agent_status('unknown-store.myshopify.com')).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')
      expect(disconnect_agent('unknown-store.myshopify.com')).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')
      expect(registration).not_to have_been_requested
    end

    it 'cannot reach an account the store app did not provision' do
      registration = stub_ai_registration
      account = create(:account)
      create(:inbox, account: account)

      connect_agent('hand-made.myshopify.com')

      expect(response).to have_http_status(:not_found)
      expect(connection_of(account)).to be_nil
      expect(registration).not_to have_been_requested
    end

    it 'is refused for an address that is not a myshopify.com domain' do
      connect_agent('shop.example.com')

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')
    end
  end

  describe 'a suspended account' do
    before do
      provision
      remove_app
    end

    let(:account) { provisioned.account }

    it 'is refused as suspended, and no agent bot is made' do
      registration = stub_ai_registration

      expect { connect_agent }.not_to(change { made_for_agent(account) })

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'account_suspended')
      expect(agent_bots_of(account)).to be_empty
      expect(registration).not_to have_been_requested
    end

    it 'still answers the status and the disconnection, with its state' do
      expect(ask_agent_status).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('never_connected')
      expect(disconnect_agent).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'never_connected', 'ai_service_told' => true)
    end
  end
end
