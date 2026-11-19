# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: what the store has', type: :request do
  include_context 'with app provisioning'

  it 'tells of an active account: its identifier, state and creation time, and nothing else' do
    provision
    account = provisioned.account
    create_list(:conversation, 2, account: account, inbox: create(:inbox, account: account))

    ask_status

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'contract' => 1, 'account_id' => account.id, 'helpdesk_url' => ProvisioningRequests::HELPDESK_URL,
      'state' => 'active', 'created_at' => account.created_at.utc.iso8601
    )
    expect(response.body).not_to match(/alex|Alex|user|conversation|contact|outcome|password/i)
  end

  it 'tells of a suspended account' do
    provision
    remove_app

    ask_status

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'suspended', 'account_id' => provisioned.account_id)
    expect(response.parsed_body.keys).to contain_exactly('contract', 'account_id', 'helpdesk_url', 'state', 'created_at')
  end

  it 'tells of an account the operator suspended by hand as suspended' do
    provision
    provisioned.account.update!(status: :suspended)

    ask_status

    expect(response.parsed_body['state']).to eq('suspended')
  end

  it 'says there is none for a store that never had an account' do
    provision

    ask_status('unknown-store.myshopify.com')
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'no_account')

    ask_status('shop.example.com')
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'no_account')
  end

  it 'finds the store whatever the case of the domain, and changes nothing' do
    provision

    expect { ask_status('Example-Store.MyShopify.com') }
      .to not_change(Inclamo::ProvisioningEvent, :count).and(not_change { provisioned.reload.updated_at })

    expect(response.parsed_body['account_id']).to eq(provisioned.account_id)
  end

  it 'refuses an unsigned question' do
    provision
    get provisioning_path

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'unauthorized')
  end
end
