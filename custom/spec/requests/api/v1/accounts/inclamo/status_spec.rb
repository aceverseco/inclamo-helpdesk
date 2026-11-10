# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo overlay status', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/status" }

  it 'refuses a request without authentication' do
    get path

    expect(response).to have_http_status(:unauthorized)
  end

  it 'tells a member of the account which versions run' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to eq(
      'overlay_version' => Inclamo::Overlay.version,
      'chatwoot_version' => Inclamo::Overlay.chatwoot_version,
      'migrations_pending' => false
    )
    expect(Inclamo::Overlay.chatwoot_version).to eq("v#{Chatwoot.config[:version]}")
  end

  it 'does not answer a user of another account' do
    outsider = create(:user, account: create(:account), role: :administrator)

    get path, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'leaves the extension hook of Chatwoot working without an Enterprise edition' do
    expect(ChatwootApp.extensions).to eq(%w[enterprise custom])
    expect { Class.new { prepend_mod_with('NoSuchExtension') } }.not_to raise_error
  end
end
