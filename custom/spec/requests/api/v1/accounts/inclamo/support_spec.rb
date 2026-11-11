# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Local Inclamo support', type: :request do
  let(:account) { create(:account) }
  let!(:author) { create(:user, account: account, role: :agent) }
  let!(:other) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/support" }
  let(:uuid) { SecureRandom.uuid }
  let(:payload) { { uuid: uuid, category: 'question', body: 'A synthetic question', files: [], context: { browser: 'Synthetic browser', location: 'conversation', transcript: 'must not leak', token: 'secret' } } }

  def submit(user = author, data = payload)
    post "#{path}/requests", params: data, headers: user.create_new_auth_token, as: :json
  end

  it 'accepts an ordinary agent without enrollment and persists one retry-safe outbox item' do
    submit
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('reference' => uuid, 'delivery' => 'queued')
    expect(response.parsed_body['context'].keys).to match_array(%w[version chatwoot_version timestamp browser location])
    submit
    expect(Inclamo::Support::Request.count).to eq(1)
    expect(Inclamo::Support::Submission.count).to eq(1)
    submit(author, payload.merge(body: 'changed content'))
    expect(response).to have_http_status(:conflict)
  end

  it 'enforces author/current administrator access on list, thread, reply and files' do
    submit
    get "#{path}/requests", headers: other.create_new_auth_token, as: :json
    expect(response.parsed_body['requests']).to eq([])
    get "#{path}/requests/#{uuid}", headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{path}/requests/#{uuid}/replies", params: { uuid: SecureRandom.uuid, body: 'forbidden' }, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{path}/requests/#{uuid}/uploads/guessed", headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    post "#{path}/requests/#{uuid}/replies", params: { uuid: SecureRandom.uuid, body: 'Admin adds details', actor: { name: 'forged' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    expect(Inclamo::Support::Submission.last.actor_snapshot).to include('name' => admin.name, 'administrator' => true)
    AccountUser.find_by!(account: account, user: admin).update!(role: :agent)
    get "#{path}/requests/#{uuid}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    AccountUser.find_by!(account: account, user: author).destroy!
    get "#{path}/requests/#{uuid}", headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps accounts separate even when the same author belongs to both' do
    submit
    second = create(:account)
    create(:account_user, account: second, user: author, role: :administrator)
    get "/api/v1/accounts/#{second.id}/inclamo/support/requests/#{uuid}", headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects empty descriptions and unauthorized staged attachments' do
    submit(author, payload.merge(body: '  '))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Inclamo::Support::Request.count).to eq(0)
    owner = AccountUser.find_by!(account: account, user: other)
    upload = Inclamo::Support::Files.stage!(bytes: 'synthetic file', filename: 'notes.txt', owner: { account_user_id: owner.id })
    submit(author, payload.merge(files: [upload.reference]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Inclamo::Support::Request.count).to eq(0)
  end

  it 'does not lose a committed request when the job queue is unavailable' do
    allow(Inclamo::Support::DeliverJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    submit
    expect(response).to have_http_status(:created)
    expect(Inclamo::Support::Submission.last.state).to eq('queued')
  end
  it 'marks only the public reply cursor actually viewed, independently for each member' do
    submit
    request = Inclamo::Support::Request.find_by!(reference: uuid)
    message = request.messages.create!(central_message_id: '123', direction: 'support', body: 'A later reply', actor: {}, files: [], sent_at: Time.current)
    request.update!(last_reply_id: message.id)
    post "#{path}/requests/#{uuid}/read", params: { cursor: 0 }, headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    get "#{path}/requests/#{uuid}", headers: author.create_new_auth_token, as: :json
    expect(response.parsed_body['unread']).to be(true)
    post "#{path}/requests/#{uuid}/read", params: { cursor: message.id + 1 }, headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{path}/requests/#{uuid}/read", params: { cursor: message.id }, headers: author.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    get "#{path}/requests/#{uuid}", headers: author.create_new_auth_token, as: :json
    expect(response.parsed_body['unread']).to be(false)
    get "#{path}/requests/#{uuid}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['unread']).to be(true)
  end

end
