# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/erasure_requests')
require Rails.root.join('custom/spec/support/ai_service_stubs')

# What a due erasure destroys, what it keeps, the people of the account, the
# stored files, and when it counts as complete (docs/app-store-erasure.md §3.4).
RSpec.describe Inclamo::Erasure::Store, type: :request do
  include_context 'with app provisioning'
  include ErasureRequests
  include AiServiceStubs

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }
  let(:administrator) { User.from_email('alex@example.test') }

  around { |example| travel_to(now) { example.run } }

  before { suspended_store }

  # The request, and the daily run after the waiting time.
  def erase!
    ask_erasure
    expect(response.parsed_body['state']).to eq('scheduled')
    travel 7.days + 1.minute
    run_erasures
  end

  def blob_file_exists?(blob)
    ActiveStorage::Blob.service.exist?(blob.key)
  end

  describe 'an account with everything in it' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, :with_avatar, account: account, email: 'pat@example.com', phone_number: '+15556251199') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
    let!(:message) { create(:message, :with_attachment, account: account, inbox: inbox, conversation: conversation) }
    let(:connection) { connect_ai_agent(account, [inbox]) }

    before do
      resolve_ai_service_publicly
      stub_ai_removal
      label = create(:label, account: account, title: 'vip')
      conversation.update_labels([label.title])
      create(:note, account: account, contact: contact, user: administrator)
      create(:team, account: account)
      create(:macro, account: account, created_by: administrator)
      create(:reporting_events_rollup, account: account)
      # The store connection the store app's keys made, as an account the
      # app provisioned has it, with a key still on it, and store answers
      # the panel read lately.
      create(:inclamo_shopify_connection, account: account, auth_kind: 'app_key', client_id: nil, client_secret: nil,
                                          access_token: 'key-from-the-app', token_expires_at: 50.minutes.from_now)
      Inclamo::Shopify::OrderReader.forget!(account.id)
      Inclamo::SetupState.insert!({ account_id: account.id, reviews: {} })
      Inclamo::AiPolicy.insert!({ account_id: account.id, action: 'cancel', mode: 'propose', limits: {} })
      Inclamo::AiProposal.insert!({ account_id: account.id, conversation_id: conversation.id, agent_bot_id: connection.agent_bot_id,
                                    request_id: 'request-1', request_digest: 'digest', review_digest: 'digest', action: 'cancel',
                                    payload: '{}', expires_at: 1.day.from_now })
      Inclamo::AiIdentityVerification.insert!({ account_id: account.id, contact_inbox_id: contact_inbox.id, user_id: administrator.id,
                                                customer_id: 'gid://shopify/Customer/1', identity_digest: 'digest' })
      Inclamo::OrderAction.insert!({ account_id: account.id, conversation_id: conversation.id, user_id: administrator.id,
                                     action_id: 'action-cancel-1', action: 'cancel', order_id: 'gid://shopify/Order/1' })
      Inclamo::CallConversation.insert!({ account_id: account.id, call_id: 'call-1', conversation_id: conversation.id,
                                          contact_id: contact.id, created_at: Time.current })
    end

    it 'destroys it whole, tells the AI service, and leaves no row naming it' do
      generation = Inclamo::Shopify::OrderReader.generation_key(account.id)
      expect(Redis::Alfred.get(generation)).to be_present
      removal = stub_ai_removal
      token = AgentBot.find(connection.agent_bot_id).access_token.token
      ids = { account: account.id, conversation: conversation.id, message: message.id, contact: contact.id, inbox: inbox.id }

      erase!

      expect(Account.exists?(ids[:account])).to be(false)
      [Conversation, Message, Contact, Inbox, Label, Note, Team, Macro, CannedResponse, Attachment, AgentBot,
       ReportingEventsRollup, AccountUser, Channel::WebWidget].each do |model|
        expect(model.where(account_id: ids[:account]).count).to eq(0), "#{model.name} still has rows of the account"
      end
      [Inclamo::ShopifyConnection, Inclamo::AiConnection, Inclamo::SetupState, Inclamo::AiPolicy, Inclamo::AiProposal,
       Inclamo::AiIdentityVerification, Inclamo::OrderAction, Inclamo::CallConversation, Inclamo::TeamQueue].each do |model|
        expect(model.where(account_id: ids[:account]).count).to eq(0), "#{model.name} still has rows of the account"
      end
      expect(ContactInbox.exists?(contact_inbox.id)).to be(false)
      expect(Inclamo::ShopifyConnection.where(auth_kind: 'app_key', account_id: ids[:account])).to be_empty
      expect(Redis::Alfred.get(generation)).to be_nil
      expect(Inclamo::Erasure::Leftovers.account(ids[:account])).to eq([])
      expect(removal.with(headers: { 'Authorization' => "Bearer #{token}" })).to have_been_requested.once
      expect(provisioned).to have_attributes(state: 'erased', account_id: nil, erased_at: Time.current, erase_after: nil,
                                             storefront_inbox_id: nil, store_access_url: nil)
      expect(store_record).to have_attributes(state: 'erased', account_id: ids[:account], completed_at: Time.current)
      expect(events_of.last).to eq('erased')
    end

    it 'removes the stored files of its messages and contacts from the storage service' do
      files = [message.attachments.first.file.blob, contact.avatar.blob]
      expect(files.map { |blob| blob_file_exists?(blob) }).to eq([true, true])

      erase!

      expect(ActiveStorage::Blob.where(id: files.map(&:id))).to be_empty
      expect(files.map { |blob| blob_file_exists?(blob) }).to eq([false, false])
      expect(ActiveStorage::Attachment.where(blob_id: files.map(&:id))).to be_empty
    end

    it 'refuses the widget of the erased account as an unknown one' do
      token = provisioned.storefront_inbox.channel.website_token
      get '/widget', params: { website_token: token }
      expect(response).not_to have_http_status(:not_found)

      erase!

      get '/widget', params: { website_token: token }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the people of the account' do
    let(:other) { provision('other-store.myshopify.com', admin: { email: 'wren@example.test' }) && provisioned('other-store.myshopify.com').account }

    it 'deletes a user who belonged to this account only, and frees the email' do
      agent = create(:user, account: account, role: :agent, email: 'agent-only@example.test')
      ids = [administrator.id, agent.id]

      erase!

      expect(User.where(id: ids)).to be_empty
      expect(User.from_email('alex@example.test')).to be_nil
      expect(Inclamo::Erasure::Leftovers.users(ids)).to eq([])
      expect(create(:user, email: 'alex@example.test')).to be_persisted
      expect(store_record.user_ids).to match_array(ids)
    end

    it 'keeps a user of two accounts with the other account, the password and the role, without this one' do
      wren = create(:user, email: 'wren-two@example.test', password: 'KnownPassword1!')
      create(:account_user, account: account, user: wren, role: :administrator)
      create(:account_user, account: other, user: wren, role: :agent)

      erase!

      wren.reload
      expect(wren.valid_password?('KnownPassword1!')).to be(true)
      expect(wren.account_users.pluck(:account_id, :role)).to eq([[other.id, 'agent']])
      expect(other.reload).to be_active
      expect(store_record.user_ids).not_to include(wren.id)
    end

    it 'never deletes a super admin of the installation' do
      operator = create(:super_admin, email: 'operator@example.test')
      create(:account_user, account: account, user: operator, role: :administrator)

      erase!

      expect(User.find(operator.id)).to be_present
      expect(operator.account_users.count).to eq(0)
    end

    it 'keeps a user who joined another account while the old one was being destroyed' do
      joined = other
      allow(DeleteObjectJob).to receive(:perform_now).and_wrap_original do |original, *arguments|
        original.call(*arguments)
        create(:account_user, account: joined, user: administrator, role: :agent)
      end

      erase!

      expect(store_record.state).to eq('erased')
      expect(administrator.reload.account_users.pluck(:account_id)).to eq([joined.id])
      expect(store_record.user_ids).not_to include(administrator.id)
    end

    it 'gives a store that installs again while its old account is being destroyed a new, empty account' do
      create_list(:conversation, 2, account: account, inbox: create(:inbox, account: account))
      old_id = account.id
      ask_erasure
      travel 7.days + 1.minute
      Inclamo::ErasureCheckJob.perform_now
      expect(provisioned.state).to eq('erasing')

      provision
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('outcome' => 'created', 'state' => 'active')
      fresh = provisioned.account
      expect(fresh.id).not_to eq(old_id)
      expect(fresh.conversations.count).to eq(0)

      perform_enqueued_jobs { Inclamo::StoreErasureJob.perform_now(store_record.id) }

      expect(store_record).to have_attributes(state: 'erased', account_id: old_id)
      expect(Account.exists?(old_id)).to be(false)
      expect(provisioned).to have_attributes(state: 'active', account_id: fresh.id, erased_at: nil)
      expect(administrator.reload.account_users.pluck(:account_id)).to eq([fresh.id])
      ask_erasure
      expect(response.parsed_body).to eq('error' => 'account_active')
    end
  end

  describe 'completion' do
    let(:shopper_request) do
      Inclamo::ErasureRequest.create!(kind: 'shopper_erasure', shop_domain: ProvisioningRequests::STORE, account_id: account.id,
                                      state: 'held', received_at: now, email: 'pat@example.com', phone: '+15556251199',
                                      hold_reason: 'open payment dispute', held_at: now, delete_after: now + 14.days)
    end
    let(:data_request) do
      Inclamo::ErasureRequest.create!(kind: 'shopper_data_request', shop_domain: ProvisioningRequests::STORE, account_id: account.id,
                                      state: 'waiting', received_at: now, email: 'sam@example.com')
    end

    it 'turns the store erased only when no table names the account, and finishes its open requests about shoppers' do
      requests = [shopper_request, data_request]
      done_elsewhere = Inclamo::ErasureRequest.create!(kind: 'shopper_erasure', shop_domain: 'other-store.myshopify.com', account_id: 0,
                                                       state: 'waiting', received_at: now, email: 'kim@example.com')

      erase!

      expect(provisioned).to have_attributes(state: 'erased', account_id: nil)
      requests.each do |request|
        request.reload
        expect(request).to have_attributes(state: 'done', done_by: 'store_erasure', completed_at: Time.current,
                                           email: nil, phone: nil, hold_reason: nil)
        raw = Inclamo::ErasureRequest.connection.select_one("SELECT email, phone, hold_reason FROM inclamo_erasure_requests WHERE id = #{request.id}")
        expect(raw.values).to eq([nil, nil, nil])
      end
      expect(done_elsewhere.reload.state).to eq('waiting')
    end

    it 'stays erasing while a row of any table names the account, with an alert, and completes once it is gone' do
      account_id = account.id
      ActiveRecord::Base.connection.create_table(:inclamo_spec_leftovers) { |t| t.bigint :account_id }
      ActiveRecord::Base.connection.execute("INSERT INTO inclamo_spec_leftovers (account_id) VALUES (#{account_id})")
      allow(Rails.logger).to receive(:error)

      erase!

      expect(Account.exists?(account_id)).to be(false)
      expect(provisioned).to have_attributes(state: 'erasing', account_id: nil, erased_at: nil)
      expect(store_record.state).to eq('erasing')
      expect(Inclamo::Erasure::Leftovers.account(account_id)).to eq(['inclamo_spec_leftovers'])
      expect(Rails.logger).to have_received(:error).with(/ALERT .*rows of inclamo_spec_leftovers still name its account/)
      expect(events_of).not_to include('erased')

      ActiveRecord::Base.connection.execute('DELETE FROM inclamo_spec_leftovers')
      perform_enqueued_jobs { Inclamo::StoreErasureJob.perform_now(store_record.id) }

      expect(provisioned).to have_attributes(state: 'erased', account_id: nil, erased_at: Time.current)
      expect(store_record.state).to eq('erased')
    end

    it 'cannot be undone: nothing brings the account back' do
      account_id = account.id
      erase!

      provision
      expect(response.parsed_body['account_id']).not_to eq(account_id)
      expect(Account.exists?(account_id)).to be(false)
    end
  end
end
