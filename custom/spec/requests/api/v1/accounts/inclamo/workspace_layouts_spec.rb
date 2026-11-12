# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Workspace layout isolation and revisions', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:author) { create(:user, account: account, role: :agent) }
  let!(:other) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/workspace_layout" }
  let(:empty) { { 'schema_version' => 1, 'placements' => { 'conversation-sidebar' => [], 'workspace-header' => [] } } }

  def read(user = author)
    get path, headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  def save(layout, revision, user = author)
    put path, params: { layout: layout, revision: revision }, headers: user.create_new_auth_token, as: :json
  end

  def administer(layout, target:, revision:, **extra)
    put "#{path}/administer", params: { layout: layout, target: target, revision: revision, **extra },
                             headers: admin.create_new_auth_token, as: :json
  end

  it 'starts with all four widgets and persists an intentionally empty personal layout without touching profile preferences' do
    original = author.ui_settings
    initial = read
    expect(initial['source']).to eq('product')
    expect(initial['layout']['placements'].values.flatten.size).to eq(4)
    save(empty, initial['revision'])
    expect(response).to have_http_status(:ok)
    expect(read['layout']).to eq(empty)
    expect(author.reload.ui_settings).to eq(original)
    expect(read(other)['source']).to eq('product')
  end

  it 'rejects stale writes, including edits made before a reset' do
    initial = read
    save(empty, initial['revision'])
    saved = response.parsed_body
    delete path, params: { revision: saved['revision'] }, headers: author.create_new_auth_token, as: :json
    expect(response.parsed_body['source']).to eq('product')
    save(empty, initial['revision'])
    expect(response).to have_http_status(:conflict)
  end

  it 'keeps overrides when changing the default, but atomically invalidates them on apply-all' do
    save(empty, read['revision'])
    stale = response.parsed_body['revision']
    layout = Inclamo::WorkspaceLayout.product
    layout['placements']['workspace-header'] = []
    administer(layout, target: 'default', revision: '0')
    expect(response).to have_http_status(:ok)
    expect(read['layout']).to eq(empty)
    expect(read(other)['layout']).to eq(layout)
    administer(layout, target: 'all', revision: '1', confirmed_count: 99)
    expect(response).to have_http_status(:conflict)
    administer(layout, target: 'all', revision: '1', confirmed_count: 3)
    expect(response).to have_http_status(:ok)
    expect(read['layout']).to eq(layout)
    save(empty, stale)
    expect(response).to have_http_status(:conflict)
    save(empty, read['revision'])
    expect(response).to have_http_status(:ok)
  end

  it 'limits administrator application to a member of this account' do
    outsider = create(:user, account: create(:account), role: :agent)
    administer(empty, target: 'member', revision: '0', user_id: outsider.id)
    expect(response).to have_http_status(:not_found)
    administer(empty, target: 'member', revision: '0', user_id: author.id)
    expect(response).to have_http_status(:ok)
    expect(read['layout']).to eq(empty)
    expect(read(other)['source']).to eq('product')
  end

  it 'refuses non-admin, cross-account and removed memberships' do
    get "#{path}/administration", headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    put "#{path}/administer", params: { layout: empty, target: 'all', revision: '0', confirmed_count: 3 }, headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    outsider = create(:user, account: create(:account), role: :agent)
    read(outsider)
    expect(response).to have_http_status(:unauthorized)
    AccountUser.find_by!(account: account, user: author).destroy!
    read(author)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects duplicates, placement misuse, unsupported schema and arbitrary options' do
    revision = read['revision']
    invalid = Inclamo::WorkspaceLayout.product
    invalid['placements']['workspace-header'] << { 'id' => 'orders', 'collapsed' => false }
    save(invalid, revision)
    expect(response).to have_http_status(:unprocessable_entity)
    save(empty.merge('schema_version' => 2), revision)
    expect(response).to have_http_status(:unprocessable_entity)
    invalid = Inclamo::WorkspaceLayout.product
    invalid['placements']['workspace-header'][0]['url'] = 'https://example.test'
    save(invalid, revision)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves missing saved widgets for recovery without adding new catalog entries to a custom layout' do
    member = AccountUser.find_by!(account: account, user: author)
    saved = empty.deep_dup
    saved['placements']['workspace-header'] << { 'id' => 'removed-extension', 'collapsed' => false }
    Inclamo::WorkspacePreference.create!(account_user: member, layout: saved)
    initial = read
    expect(initial['unavailable']).to eq(['removed-extension'])
    expect(initial['layout']).to eq(saved)
    save(saved, initial['revision'])
    expect(response).to have_http_status(:ok)
    save(empty, read['revision'])
    expect(read['unavailable']).to eq([])
  end
end
