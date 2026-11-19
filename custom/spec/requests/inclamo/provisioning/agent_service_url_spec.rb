# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/agent_provisioning_requests')

# The agent's credentials go only to an AI service address the operator
# listed (design D3, task 3.3). Anything else is refused before anything is
# created and before any request leaves the helpdesk.
RSpec.describe 'App agent connection: the allowed AI service addresses', type: :request do
  include_context 'with the store app and the AI service'

  before { provision }

  let(:account) { provisioned.account }

  def expect_refused(code)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => code)
    expect(response.parsed_body['message']).to be_a(String)
    expect(agent_bots_of(account)).to be_empty
    expect(account.inboxes.where(name: 'Phone')).to be_empty
    expect(connection_of(account)).to be_nil
    expect(a_request(:any, /./)).not_to have_been_made
  end

  it 'connects with a listed address, a trailing slash or the letters of the host aside' do
    registration = stub_ai_registration

    connect_agent(with: { service_url: 'https://AI.example.com/' })

    expect(response).to have_http_status(:created)
    expect(registration).to have_been_requested.once
    expect(connection_of(account).service_url).to eq(AiServiceStubs::AI_SERVICE_URL)
  end

  it 'refuses an address that is not listed, without a request to it' do
    connect_agent(with: { service_url: 'https://attacker.example.net' })

    expect_refused('service_url_not_allowed')
  end

  it 'refuses a listed origin with another path, and a listed path prefix with more after it' do
    with_modified_env INCLAMO_APP_AGENT_SERVICE_URLS: 'https://ai.example.com/channels/helpdesk' do
      connect_agent(with: { service_url: 'https://ai.example.com' })
      expect_refused('service_url_not_allowed')
      connect_agent(with: { service_url: 'https://ai.example.com/channels/helpdesk/other' })
      expect_refused('service_url_not_allowed')
      connect_agent(with: { service_url: 'https://ai.example.com/channels' })
      expect_refused('service_url_not_allowed')
    end
  end

  it 'refuses an address that is not HTTPS, listed or not' do
    with_modified_env INCLAMO_APP_AGENT_SERVICE_URLS: 'http://ai.example.com,https://ai.example.com' do
      connect_agent(with: { service_url: 'http://ai.example.com' })
      expect_refused('service_url_invalid')
    end
  end

  it 'refuses what does not read as an address' do
    ['not an address', '', nil, 42, 'https://', 'https://user:pass@ai.example.com', 'https://ai.example.com?x=1'].each do |value|
      connect_agent(with: { service_url: value })
      expect_refused('service_url_invalid')
    end
  end

  it 'refuses every address on an installation that listed none' do
    with_modified_env INCLAMO_APP_AGENT_SERVICE_URLS: nil do
      connect_agent
      expect_refused('service_url_not_allowed')
    end
    with_modified_env INCLAMO_APP_AGENT_SERVICE_URLS: ' , not-an-address ,http://ai.example.com' do
      connect_agent
      expect_refused('service_url_not_allowed')
    end
  end

  it 'allows several addresses, each on its own' do
    with_modified_env INCLAMO_APP_AGENT_SERVICE_URLS: 'https://other-ai.example.org/agent, https://ai.example.com' do
      registration = stub_ai_registration

      connect_agent

      expect(response).to have_http_status(:created)
      expect(registration).to have_been_requested.once

      provision('second-store.myshopify.com')
      second = stub_request(:post, 'https://other-ai.example.org/agent/connections')
               .to_return(status: 201, body: { connection_id: 'conn-2', webhook_url: 'https://other-ai.example.org/agent/hooks/2' }.to_json,
                          headers: AiServiceStubs::AI_JSON_HEADERS)
      connect_agent('second-store.myshopify.com', with: { service_url: 'https://other-ai.example.org/agent' })

      expect(response).to have_http_status(:created)
      expect(second).to have_been_requested.once
      expect(connection_of(account).reload.service_url).to eq(AiServiceStubs::AI_SERVICE_URL)
    end
  end

  it "leaves the page's codes unrestricted by the list" do
    registration = stub_request(:post, 'https://unlisted-ai.example.org/connections')
                   .to_return(status: 201, body: { connection_id: 'conn-9', webhook_url: 'https://unlisted-ai.example.org/hooks/9' }.to_json,
                              headers: AiServiceStubs::AI_JSON_HEADERS)
    administrator = User.from_email('alex@example.test')
    website = create(:inbox, account: account)

    post "/api/v1/accounts/#{account.id}/inclamo/ai/connection",
         params: { connection_code: ai_code(service_url: 'https://unlisted-ai.example.org'), inbox_ids: [website.id] },
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(registration).to have_been_requested.once
    expect(connection_of(account)).to have_attributes(connected_via: 'page', connected_by: administrator)
  end
end
