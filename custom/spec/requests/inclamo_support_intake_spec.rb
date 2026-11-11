# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Source-scoped central support intake', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:key) { OpenSSL::PKey.generate_key('ED25519') }
  let(:source) do
    Inclamo::Support::Source.create!(reference: SecureRandom.uuid, fingerprint: Inclamo::Support::Authentication.fingerprint(key.public_to_pem),
                                    public_key: key.public_to_pem, base_url: 'https://synthetic.example.test')
  end
  let(:payload) do
    { 'uuid' => SecureRandom.uuid, 'request_reference' => SecureRandom.uuid, 'account_key' => 'account:19',
      'initial' => true, 'category' => 'problem', 'author' => { 'key' => 'user:1', 'name' => 'Synthetic Author', 'email' => 'author@example.test' },
      'actor' => { 'key' => 'user:1', 'name' => 'Synthetic Author', 'administrator' => false },
      'context' => { 'version' => '0.1.0', 'location' => 'inbox' }, 'body' => 'Synthetic report', 'files' => [], 'hosted' => true }
  end

  around do |example|
    with_modified_env INCLAMO_SUPPORT_CENTRAL: 'true', INCLAMO_SUPPORT_ACCOUNT_ID: account.id.to_s, INCLAMO_SUPPORT_INBOX_ID: inbox.id.to_s do
      example.run
    end
  end

  def signed(method, suffix, value = nil, signing_key: key, source_id: source.reference)
    path = "/inclamo/support/v1/#{suffix}"
    body = value ? JSON.generate(value) : ''
    timestamp = Time.now.to_i.to_s
    headers = { 'CONTENT_TYPE' => 'application/json', 'X-Inclamo-Source' => source_id, 'X-Inclamo-Timestamp' => timestamp,
                'X-Inclamo-Signature' => Inclamo::Support::Authentication.sign(signing_key.private_to_pem, method.to_s.upcase, path, timestamp, body) }
    public_send(method, path, params: body, headers: headers)
  end

  it 'enrolls by proof of possession, recovers repeated enrollment and ignores hosted claims' do
    2.times do
      signed(:post, 'register', { public_key: key.public_to_pem, base_url: 'https://synthetic.example.test', hosted: true })
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['source_id']).to eq(source.reference)
    end
    expect(source.reload).not_to be_hosted
    expect(Inclamo::Support::Source.count).to eq(1)
  end

  it 'atomically creates one native conversation/message and rejects changed UUID content after a lost acknowledgement' do
    signed(:post, 'submissions', payload)
    expect(response).to have_http_status(:ok)
    result = response.parsed_body
    signed(:post, 'submissions', payload)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(result)
    expect(Inclamo::Support::Receipt.count).to eq(1)
    expect(inbox.conversations.count).to eq(1)
    conversation = inbox.conversations.last
    expect(conversation.messages.incoming.count).to eq(1)
    expect(conversation.messages.incoming.last.content).to include('Self-hosted', 'Synthetic report')
    expect(conversation.custom_attributes['inclamo_support_origin']).to eq('self_hosted')
    signed(:post, 'submissions', payload.merge('body' => 'changed'))
    expect(response).to have_http_status(:conflict)
  end

  it 'marks centrally registered hosting and attributes an administrator follow-up to its actual sender' do
    source.update!(hosted: true)
    signed(:post, 'submissions', payload)
    expect(response).to have_http_status(:ok)
    mapping = source.requests.last
    expect(mapping.conversation.custom_attributes['inclamo_support_origin']).to eq('hosted')
    admin_payload = payload.merge('uuid' => SecureRandom.uuid, 'initial' => false, 'body' => 'Admin follow-up',
                                  'actor' => { 'key' => 'user:2', 'name' => 'Synthetic Admin', 'administrator' => true })
    signed(:post, 'submissions', admin_payload)
    expect(response).to have_http_status(:ok)
    message = mapping.conversation.messages.incoming.order(:id).last
    expect(message.sender.name).to eq('Synthetic Admin')
    expect(message.content).to include('(administrator)')
    expect(mapping.reload.author_key).to eq('user:1')
  end

  it 'rejects a wrong signature and another source request reference' do
    signed(:post, 'submissions', payload)
    reference = response.parsed_body['reference']
    second_key = OpenSSL::PKey.generate_key('ED25519')
    signed(:get, 'events?cursor=0', signing_key: second_key)
    expect(response).to have_http_status(:unauthorized)
    second = Inclamo::Support::Source.create!(reference: SecureRandom.uuid, fingerprint: Inclamo::Support::Authentication.fingerprint(second_key.public_to_pem), public_key: second_key.public_to_pem, base_url: 'https://second.example.test')
    signed(:post, "requests/#{reference}/reconcile", {}, signing_key: second_key, source_id: second.reference)
    expect(response).to have_http_status(:not_found)
  end

  it 'excludes private notes and their attachments from feed storage and serializes public replies once' do
    signed(:post, 'submissions', payload)
    mapping = source.requests.last
    private_note = create(:message, account: account, inbox: inbox, conversation: mapping.conversation, private: true, content: 'secret internal note', message_type: :outgoing)
    reply = create(:message, account: account, inbox: inbox, conversation: mapping.conversation, private: false, content: 'public answer', message_type: :outgoing)
    2.times { Inclamo::Support::Feed.reconcile!(mapping) }
    expect(Inclamo::Support::Event.where(central_request: mapping).where("identity LIKE ?", "message:#{private_note.id}:%")).to be_empty
    expect(Inclamo::Support::Event.where(central_request: mapping).where("identity LIKE ?", "message:#{reply.id}:%").count).to eq(1)
    signed(:get, 'events?cursor=0')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('public answer')
    expect(response.body).not_to include('secret internal note')
    reply.update!(private: true)
    signed(:get, 'events?cursor=0')
    expect(response.body).not_to include('public answer')
    expect(response.body).to include('removed')
  end

  it 'fails before text creation when attachments are missing and retries on one thread after upload' do
    reference = SecureRandom.uuid
    report = payload.merge('files' => [reference])
    signed(:post, 'submissions', report)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(inbox.conversations.count).to eq(0)
    2.times do
      signed(:post, 'uploads', { reference: reference, filename: 'notes.txt', bytes: Base64.strict_encode64('synthetic attachment') })
      expect(response).to have_http_status(:ok)
    end
    2.times { signed(:post, 'submissions', report) }
    expect(response).to have_http_status(:ok)
    expect(inbox.conversations.count).to eq(1)
    expect(inbox.conversations.last.messages.incoming.last.attachments.count).to eq(1)
    signed(:post, 'uploads', { reference: SecureRandom.uuid, filename: 'image.png', bytes: Base64.strict_encode64('<svg><script>bad()</script></svg>') })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps central routes disabled on a client deployment' do
    with_modified_env INCLAMO_SUPPORT_CENTRAL: nil do
      signed(:post, 'submissions', payload)
      expect(response).to have_http_status(:not_found)
    end
  end
  it 'repairs missing attachment storage and associations without duplicating the delivered text' do
    reference = SecureRandom.uuid
    bytes = Base64.strict_encode64('synthetic attachment repair')
    signed(:post, 'uploads', { reference: reference, filename: 'notes.txt', bytes: bytes })
    report = payload.merge('files' => [reference])
    signed(:post, 'submissions', report)
    expect(response.parsed_body['state']).to eq('delivered')
    receipt = Inclamo::Support::Receipt.last
    blob = Inclamo::Support::Upload.find_by!(reference: reference).file.blob
    blob.service.delete(blob.key)
    signed(:post, 'submissions', report)
    expect(response.parsed_body['state']).to eq('attachments_pending')
    signed(:post, 'uploads', { reference: reference, filename: 'notes.txt', bytes: bytes })
    expect(response).to have_http_status(:ok)
    receipt.message.attachments.first.file.detach
    receipt.message.attachments.delete_all
    signed(:post, 'submissions', report)
    expect(response.parsed_body['state']).to eq('delivered')
    expect(receipt.message.reload.attachments.size).to eq(1)
    expect(receipt.message.attachments.first.file.download).to eq('synthetic attachment repair')
    expect(inbox.conversations.count).to eq(1)
    expect(inbox.conversations.last.messages.incoming.count).to eq(1)
  end

  it 'respects native soft deletion on cached feeds and receipt replay' do
    signed(:post, 'submissions', payload)
    mapping = source.requests.last
    message = mapping.conversation.messages.incoming.last
    Inclamo::Support::Feed.reconcile!(mapping)
    message.update!(content: 'This message was deleted', content_attributes: { deleted: true })
    signed(:get, 'events?cursor=0')
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Synthetic report')
    expect(response.body).to include('removed')
    signed(:post, 'submissions', payload)
    expect(response).to have_http_status(:conflict)
    expect(message.reload.content).to eq('This message was deleted')
    expect(mapping.conversation.messages.incoming.count).to eq(1)
  end

  it 'bounds feed batches by bytes without advancing over an unsent event' do
    signed(:post, 'submissions', payload)
    mapping = source.requests.last
    3.times { create(:message, account: account, inbox: inbox, conversation: mapping.conversation, private: false, content: 'A' * 1000, message_type: :outgoing) }
    Inclamo::Support::Feed.reconcile!(mapping)
    stub_const('Inclamo::Support::IntakeController::FEED_BYTES', 1200)
    cursor = 0
    seen = []
    loop do
      signed(:get, "events?cursor=#{cursor}")
      expect(response).to have_http_status(:ok)
      batch = response.parsed_body
      seen.concat(batch['events'].map { |event| event['id'] })
      expect(batch['cursor']).to be > cursor
      cursor = batch['cursor']
      break unless batch['more']
    end
    expect(seen).to eq(Inclamo::Support::Event.where(source: source).order(:id).pluck(:id))
    expect(seen.uniq).to eq(seen)
  end

end
