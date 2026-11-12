# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Support delivery, verification and unread state' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account: account, role: :agent) }
  let(:member) { AccountUser.find_by!(account: account, user: author) }
  let(:support_account) { create(:account) }
  let(:inbox) { create(:inbox, account: support_account, channel: create(:channel_api, account: support_account)) }
  let(:key) { OpenSSL::PKey.generate_key('ED25519') }
  let(:source) { Inclamo::Support::Source.create!(reference: SecureRandom.uuid, public_key: key.public_to_pem, fingerprint: Inclamo::Support::Authentication.fingerprint(key.public_to_pem), base_url: 'https://synthetic.example.test') }
  let(:local) do
    Inclamo::Support::LocalRequests.new(member).create!('uuid' => SecureRandom.uuid, 'category' => 'question', 'body' => 'Synthetic issue', 'files' => [])
  end

  around do |example|
    delivery_method = Inclamo::Support::Mailer.delivery_method
    Inclamo::Support::Mailer.delivery_method = :test
    with_modified_env INCLAMO_SUPPORT_CENTRAL: 'true', INCLAMO_SUPPORT_ACCOUNT_ID: support_account.id.to_s, INCLAMO_SUPPORT_INBOX_ID: inbox.id.to_s do
      example.run
    end
  ensure
    Inclamo::Support::Mailer.delivery_method = delivery_method
  end

  def mapping
    @mapping ||= begin
      submission = local.submissions.first
      value = { 'uuid' => submission.uuid, 'request_reference' => local.reference, 'account_key' => "account:#{account.id}",
                'initial' => true, 'category' => 'question', 'author' => local.author_snapshot, 'actor' => submission.actor_snapshot,
                'context' => local.context, 'body' => submission.body, 'files' => [] }
      Inclamo::Support::Intake.new(source).submit!(value)
      source.requests.last
    end
  end

  def public_reply(content = 'Public response')
    create(:message, account: support_account, inbox: inbox, conversation: mapping.conversation, message_type: :outgoing, private: false, content: content)
  end

  it 'recovers a lost acknowledgement using the same submission UUID and native receipt' do
    submission = local.submissions.first
    transport = Inclamo::Support::Transport.new
    allow(Inclamo::Support::Transport).to receive(:new).and_return(transport)
    allow(transport).to receive(:enroll!)
    calls = 0
    central_source = source
    transport.define_singleton_method(:call) do |_method, _path, value|
      result = Inclamo::Support::Intake.new(central_source).submit!(value.deep_stringify_keys).stringify_keys
      calls += 1
      raise Inclamo::Support::Unavailable if calls == 1

      result
    end
    expect { transport.deliver!(submission) }.to raise_error(Inclamo::Support::Unavailable)
    expect(submission.reload.state).to eq('queued')
    expect(Inclamo::Support::Receipt.count).to eq(1)
    submission.update!(next_attempt_at: nil)
    Inclamo::Support::DeliverJob.perform_now(submission.id)
    expect(submission.reload.state).to eq('delivered')
    expect(Inclamo::Support::Receipt.count).to eq(1)
    expect(inbox.conversations.count).to eq(1)
    expect(inbox.conversations.last.messages.incoming.count).to eq(1)
  end

  it 'keeps per-member unread state, imports duplicate events once and excludes notes' do
    reply = public_reply
    create(:message, account: support_account, inbox: inbox, conversation: mapping.conversation, message_type: :outgoing, private: true, content: 'Secret private note')
    Inclamo::Support::Feed.reconcile!(mapping)
    2.times do
      Inclamo::Support::Event.order(:id).each { |event| Inclamo::Support::Feed.import!({ 'id' => event.id }.merge(Inclamo::Support::Feed.safe_payload(event))) }
    end
    local.reload
    expect(local.messages.where(central_message_id: reply.id.to_s).count).to eq(1)
    expect(local.messages.pluck(:body).join).not_to include('Secret private note')
    service = Inclamo::Support::LocalRequests.new(member)
    expect(service.serialize(local)[:unread]).to be(true)
    local.reads.create!(account_user: member, last_reply_id: local.last_reply_id)
    expect(service.serialize(local)[:unread]).to be(false)
    admin = create(:user, account: account, role: :administrator)
    expect(Inclamo::Support::LocalRequests.new(AccountUser.find_by!(account: account, user: admin)).serialize(local)[:unread]).to be(true)
  end

  it 'requires self-hosted recipient verification, retries email independently and deduplicates notifications' do
    mapping
    identity = { 'account_key' => "account:#{account.id}", 'actor_key' => local.author_key }
    input = identity.merge('email' => author.email, 'active' => true, 'locally_verified' => true)
    Inclamo::Support::Recipients.sync!(source, 'recipients' => [input])
    recipient = Inclamo::Support::Recipient.last
    expect(recipient.verified_at).to be_nil
    expect { public_reply; Inclamo::Support::Feed.reconcile!(mapping) }.not_to change(Inclamo::Support::Delivery, :count)
    ActionMailer::Base.deliveries.clear
    Inclamo::Support::Recipients.sync!(source, 'recipients' => [input.merge('request_verification' => true)])
    code = ActionMailer::Base.deliveries.last.body.decoded[/\b\d{6}\b/]
    expect(code).to be_present
    expect { Inclamo::Support::Recipients.verify!(source, identity.merge('code' => 'invalid')) }.to raise_error(Inclamo::Support::Invalid)
    expect(recipient.reload.verification_attempts).to eq(1)
    Inclamo::Support::Recipients.verify!(source, identity.merge('code' => code))
    answer = public_reply('Do not put this body or screenshots into email')
    2.times { Inclamo::Support::Feed.reconcile!(mapping) }
    expect(Inclamo::Support::Delivery.count).to eq(1)
    delivery = Inclamo::Support::Delivery.last
    failure = double(deliver_now: nil)
    allow(failure).to receive(:deliver_now).and_raise(Net::SMTPServerBusy)
    allow(Inclamo::Support::Mailer).to receive(:notification).and_return(failure)
    Inclamo::Support::NotifyJob.perform_now(delivery.id)
    expect(delivery.reload.delivered_at).to be_nil
    expect(answer.reload.content).to include('Do not put')
    allow(Inclamo::Support::Mailer).to receive(:notification).and_call_original
    delivery.update!(next_attempt_at: nil)
    2.times { Inclamo::Support::NotifyJob.perform_now(delivery.id) }
    expect(ActionMailer::Base.deliveries.size).to eq(2) # verification + one notification
    email = ActionMailer::Base.deliveries.last.body.decoded
    expect(email).to include(local.reference, '/app/accounts/')
    expect(email).not_to include(answer.content, 'access-token', 'Secret')
    Inclamo::Support::Recipients.sync!(source, 'recipients' => [identity.merge('active' => false)])
    expect(recipient.reload).not_to be_active
    expect(recipient.verified_at).to be_nil
  end

  it 'refuses expired signatures, oversized/active content, and cleans only unattached staging' do
    expect do
      Inclamo::Support::Authentication.verify!(key.public_to_pem, 'invalid', 'POST', '/test', (Time.now.to_i - 600).to_s, '')
    end.to raise_error(Inclamo::Support::Unauthorized)
    expect { Inclamo::Support::Files.validate!('x' * (Inclamo::Support::MAX_BYTES + 1), filename: 'large.txt') }.to raise_error(Inclamo::Support::Invalid, 'file_size')
    expect { Inclamo::Support::Files.validate!('<html><script>x</script></html>', filename: 'safe.txt') }.to raise_error(Inclamo::Support::Invalid, 'file_type')
    stale = Inclamo::Support::Files.stage!(bytes: 'staged synthetic', filename: 'notes.txt', owner: { account_user_id: member.id })
    stale.update!(created_at: 25.hours.ago)
    kept = Inclamo::Support::Files.stage!(bytes: 'attached synthetic', filename: 'notes.txt', owner: { account_user_id: member.id })
    kept.update!(created_at: 25.hours.ago, submission_id: local.submissions.first.id)
    Inclamo::Support::Files.clean_staging!
    expect(Inclamo::Support::Upload.exists?(stale.id)).to be(false)
    expect(Inclamo::Support::Upload.exists?(kept.id)).to be(true)
  end
  it 'removes a deleted public reply from an already synchronized client' do
    reply = public_reply
    Inclamo::Support::Feed.reconcile!(mapping)
    first_events = Inclamo::Support::Event.order(:id).to_a
    first_events.each { |event| Inclamo::Support::Feed.import!(Inclamo::Support::Feed.safe_payload(event)) }
    expect(local.messages.where(central_message_id: reply.id.to_s)).to exist
    reply.destroy!
    Inclamo::Support::Feed.reconcile!(mapping)
    Inclamo::Support::Event.where('id > ?', first_events.last.id).each { |event| Inclamo::Support::Feed.import!(Inclamo::Support::Feed.safe_payload(event)) }
    expect(local.messages.where(central_message_id: reply.id.to_s)).not_to exist
  end

  it 'bounds declared and chunked bodies before the downstream parser runs' do
    parser = double(call: [200, {}, ['ok']])
    middleware = InclamoSupportBodyLimit.new(parser)
    limit = Inclamo::Support::MAX_BODY * 4 + 65_536
    ['','1000000'].each do |length|
      env = { 'PATH_INFO' => '/inclamo/support/v1/submissions', 'CONTENT_LENGTH' => length, 'rack.input' => StringIO.new('x' * (limit + 1)) }
      expect(middleware.call(env).first).to eq(413)
    end
    expect(parser).not_to have_received(:call)
    valid = { 'PATH_INFO' => '/api/v1/accounts/1/inclamo/support/requests', 'rack.input' => StringIO.new('valid') }
    expect(middleware.call(valid).first).to eq(200)
    expect(valid['rack.input'].read).to eq('valid')
  end

  it 'encrypts the installation private key using the deployment secret' do
    installation = Inclamo::Support::Installation.identity
    encrypted = installation.read_attribute(:private_key)
    expect(encrypted).not_to include('PRIVATE KEY')
    expect(installation.reload.private_key).to include('PRIVATE KEY')
    expect(Inclamo::Support::Installation.identity.id).to eq(installation.id)
  end

  it 'bounds enrollment rates and operationally rotates unused clones or revokes a source without deleting history' do
    2.times { Inclamo::Support::Authentication.rate!('synthetic-limit', limit: 2) }
    expect { Inclamo::Support::Authentication.rate!('synthetic-limit', limit: 2) }.to raise_error(Inclamo::Support::RateLimited)
    require 'rake'
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    load Rails.root.join('custom/lib/tasks/inclamo_support.rake') unless Rake::Task.task_defined?('inclamo:support:new_clone_identity')
    original = Inclamo::Support::Installation.identity.public_key
    rotation = Rake::Task['inclamo:support:new_clone_identity']; rotation.reenable; rotation.invoke
    expect(Inclamo::Support::Installation.identity.public_key).not_to eq(original)
    mapping
    rotation.reenable
    expect { rotation.invoke }.to raise_error(SystemExit)
    native_id = mapping.conversation_id
    trust = Rake::Task['inclamo:support:trust_hosted']; trust.reenable; trust.invoke(source.reference, source.fingerprint)
    expect(source.reload).to be_hosted
    revoke = Rake::Task['inclamo:support:revoke_source']; revoke.reenable; revoke.invoke(source.reference, source.fingerprint)
    expect(source.reload.revoked_at).to be_present
    expect(Conversation.exists?(native_id)).to be(true)
  end

end
