# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

# Two requests for one store's storefront inbox at the same moment. Each is a
# whole signed `PUT` in a thread of its own, with its own database connection,
# and has to see the other's commit: so this example runs outside the
# transaction the other examples are wrapped in and removes what it made.
RSpec.describe 'App storefront chat: two requests at the same moment', type: :request do
  self.use_transactional_tests = false

  include_context 'with app provisioning'

  let(:domain) { "concurrent-chat-#{SecureRandom.hex(4)}.myshopify.com" }
  let(:account) { Account.find_by!(name: name) }
  let(:name) { "Concurrent Chat #{SecureRandom.hex(4)}" }
  let(:email) { "concurrent-chat-#{SecureRandom.hex(4)}@example.test" }

  before do
    made = create(:account, name: name)
    create(:user, account: made, role: :administrator, email: email)
    Inclamo::Provisioning.link!(domain, made.id)
  end

  after do
    account_ids = Account.where(name: name).pluck(:id)
    inbox_ids = Inbox.where(account_id: account_ids).pluck(:id)
    user_ids = User.where(email: email).pluck(:id)
    Inclamo::ProvisioningEvent.where(shop_domain: domain).delete_all
    Inclamo::ProvisionedAccount.where(shop_domain: domain).delete_all
    InboxMember.where(inbox_id: inbox_ids).delete_all
    Inbox.where(id: inbox_ids).delete_all
    Channel::WebWidget.where(account_id: account_ids).delete_all
    NotificationSetting.where(account_id: account_ids).or(NotificationSetting.where(user_id: user_ids)).delete_all
    AccountUser.where(account_id: account_ids).delete_all
    CannedResponse.where(account_id: account_ids).delete_all
    Label.where(account_id: account_ids).delete_all
    Account.where(id: account_ids).delete_all
    User.where(id: user_ids).delete_all
  end

  # Sends `count` signed PUTs together and returns each one's status and body.
  def put_together(count)
    path = provisioning_path(domain, '/storefront-chat')
    raw = JSON.generate(contract: 1, storefront_url: 'https://concurrent.example')
    start = Queue.new
    threads = Array.new(count) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          timestamp = Time.now.to_i
          request_id = SecureRandom.uuid
          signature = Inclamo::Provisioning::Signature.sign(ProvisioningRequests::SECRET, timestamp: timestamp, request_id: request_id,
                                                                                         method: 'PUT', path: path, body: raw)
          session = ActionDispatch::Integration::Session.new(Rails.application)
          start.pop
          session.put(path, params: raw, headers: {
                        'CONTENT_TYPE' => 'application/json', 'X-Inclamo-Timestamp' => timestamp.to_s,
                        'X-Inclamo-Request-Id' => request_id, 'X-Inclamo-Signature' => signature
                      })
          [session.response.status, session.response.parsed_body]
        end
      end
    end
    count.times { start << :go }
    threads.map(&:value)
  end

  it 'ends with one inbox, and answers both with the same token' do
    # The first to take the store's row is held inside its transaction, so the
    # second certainly arrives while the first has not finished.
    allow(Channel::WebWidget).to receive(:create!).and_wrap_original do |original, *arguments, **options|
      sleep 0.5
      original.call(*arguments, **options)
    end

    answers = put_together(2)

    inboxes = Inbox.where(account_id: account.id)
    expect(inboxes.count).to eq(1)
    expect(Channel::WebWidget.where(account_id: account.id).count).to eq(1)
    expect(Channel::WebWidget).to have_received(:create!).once
    expect(answers.map(&:first)).to contain_exactly(201, 200)
    expect(answers.map { |_status, body| body['outcome'] }).to contain_exactly('created', 'existed')
    expect(answers.map { |_status, body| body['website_token'] }.uniq).to eq([inboxes.first.channel.website_token])
    expect(answers.map { |_status, body| body['inbox_id'] }.uniq).to eq([inboxes.first.id])
    expect(Inclamo::ProvisionedAccount.find_by!(shop_domain: domain).storefront_inbox_id).to eq(inboxes.first.id)
    expect(InboxMember.where(inbox_id: inboxes.first.id).count).to eq(1)
    expect(Inclamo::ProvisioningEvent.where(shop_domain: domain).pluck(:outcome)).to contain_exactly('chat_created', 'chat_existed')
  end

  it 'ends with one inbox when three arrive together' do
    answers = put_together(3)

    expect(Inbox.where(account_id: account.id).count).to eq(1)
    expect(answers.map(&:first).sort).to eq([200, 200, 201])
    expect(answers.map { |_status, body| body['website_token'] }.uniq.size).to eq(1)
  end
end
