# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App storefront chat: the inbox made with the account', type: :request do
  include_context 'with app provisioning'

  let(:store) { ProvisioningRequests::STORE }
  let(:administrator) { User.from_email('alex@example.test') }

  def nothing_created
    not_change(Inbox, :count).and not_change(Channel::WebWidget, :count).and not_change(InboxMember, :count)
  end

  describe 'a store without an account' do
    it 'gets its storefront inbox with the account: one website inbox, named after the store, at the store\'s Shopify address' do
      expect { provision }.to change(Inbox, :count).by(1).and change(Channel::WebWidget, :count).by(1)

      account = provisioned.account
      inbox = storefront_inbox
      expect(account.inboxes).to contain_exactly(inbox)
      expect(inbox.channel).to be_a(Channel::WebWidget)
      expect(inbox).to have_attributes(name: 'Example Store', account_id: account.id)
      expect(inbox.channel).to have_attributes(website_url: "https://#{store}", account_id: account.id, allowed_domains: '')
      expect(inbox.members).to contain_exactly(administrator)
      expect(inbox.agent_bot).to be_nil
    end

    it 'leaves the answer of the account\'s call as it was' do
      provision

      expect(response).to have_http_status(:created)
      account = provisioned.account
      expect(response.parsed_body.except('password_setup_url')).to eq(
        'contract' => 1, 'account_id' => account.id, 'helpdesk_url' => ProvisioningRequests::HELPDESK_URL,
        'state' => 'active', 'outcome' => 'created', 'created_at' => account.created_at.utc.iso8601, 'admin_is_member' => true
      )
      expect(response.parsed_body.keys).to contain_exactly('contract', 'account_id', 'helpdesk_url', 'state', 'outcome', 'created_at',
                                                           'admin_is_member', 'password_setup_url')
      expect(response.body).not_to include(storefront_inbox.channel.website_token)
      expect(response.body).not_to include(storefront_inbox.channel.hmac_token)
      expect(Inclamo::ProvisioningEvent.pluck(:outcome)).to eq(['created'])

      ask_status
      expect(response.parsed_body.keys).to contain_exactly('contract', 'account_id', 'helpdesk_url', 'state', 'created_at')
    end

    it 'has the request for the storefront chat answer that it existed, with the token' do
      provision
      inbox = storefront_inbox

      expect { ask_for_chat(with: { storefront_url: 'https://example-store.example' }) }.to nothing_created

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'contract' => 1, 'inbox_id' => inbox.id, 'website_token' => inbox.channel.website_token,
        'widget_base_url' => ProvisioningRequests::HELPDESK_URL, 'state' => 'active', 'outcome' => 'existed'
      )
      expect(inbox.channel.reload.website_url).to eq("https://#{store}")
    end

    it 'makes the administrator a member also when the installation already knew them' do
      known = create(:user, email: 'alex@example.test')

      provision

      expect(storefront_inbox.members).to contain_exactly(known)
    end

    it 'leaves no account, no row, no user and no inbox when the inbox step fails, and the app\'s retry starts clean' do
      request_id = SecureRandom.uuid
      failures = 0
      allow(Inclamo::Provisioning::StorefrontChat).to receive(:create!).and_wrap_original do |original, row, account, *rest|
        failures += 1
        # The step fails after it has written: the channel and the inbox exist
        # inside the transaction and must go with it.
        inbox = original.call(row, account, *rest)
        raise ActiveRecord::StatementInvalid, 'the inbox step failed' if failures == 1

        inbox
      end

      expect { provision(request_id: request_id) }
        .to not_change(Account, :count).and not_change(Inclamo::ProvisionedAccount, :count).and not_change(User, :count)
        .and not_change(AccountUser, :count).and nothing_created
      expect(response).to have_http_status(:internal_server_error)
      expect(failures).to eq(1)
      expect(provisioned).to be_nil
      expect(administrator).to be_nil
      expect(Account.where(name: 'Example Store')).to be_empty

      provision(request_id: request_id)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('outcome' => 'created')
      expect(response.parsed_body['password_setup_url']).to be_present
      expect(provisioned.account.inboxes).to contain_exactly(storefront_inbox)
      expect(Account.where(name: 'Example Store').count).to eq(1)
    end

    it 'leaves nothing behind when the channel cannot be made' do
      allow(Channel::WebWidget).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'the channel was not made')

      expect { provision }
        .to not_change(Account, :count).and not_change(Inclamo::ProvisionedAccount, :count).and not_change(User, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(Channel::WebWidget).to have_received(:create!).once
    end
  end

  describe 'an account that is not created by the request' do
    it 'gets no inbox when it existed, whoever asks' do
      provision
      storefront_inbox.destroy!

      expect do
        provision
        provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
      end.to nothing_created

      expect(response.parsed_body['outcome']).to eq('existed')
      expect(storefront_inbox).to be_nil
      expect(provisioned.account.inboxes).to be_empty
    end

    it 'does not get a second inbox when it existed with one' do
      provision
      inbox = storefront_inbox

      expect { provision }.to nothing_created
      expect(storefront_inbox).to eq(inbox)
    end

    it 'gets no inbox when it is restored after the team deleted the storefront inbox, until the app asks for one' do
      provision
      old_token = storefront_inbox.channel.website_token
      perform_enqueued_jobs do
        delete "/api/v1/accounts/#{provisioned.account_id}/inboxes/#{storefront_inbox.id}", headers: administrator.create_new_auth_token, as: :json
      end
      remove_app

      expect { provision }.to nothing_created

      expect(response.parsed_body).to include('outcome' => 'restored', 'state' => 'active')
      expect(storefront_inbox).to be_nil
      ask_chat_status
      expect(response.parsed_body).to eq('error' => 'no_storefront_chat')

      ask_for_chat
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['website_token']).not_to eq(old_token)
    end

    it 'keeps its inbox and token when it is restored with one' do
      provision
      inbox = storefront_inbox
      token = inbox.channel.website_token
      remove_app

      expect { provision }.to nothing_created

      expect(storefront_inbox).to eq(inbox)
      ask_for_chat
      expect(response.parsed_body).to include('outcome' => 'existed', 'website_token' => token, 'state' => 'active')
    end

    it 'gets no inbox when it was made by hand and linked, until the app asks for one' do
      account = linked_account(name: 'Made By Hand')
      create(:user, account: account, role: :administrator)

      expect { provision }.to nothing_created

      expect(response.parsed_body).to include('outcome' => 'existed', 'account_id' => account.id)
      expect(storefront_inbox).to be_nil
      ask_chat_status
      expect(response.parsed_body).to eq('error' => 'no_storefront_chat')

      ask_for_chat
      expect(response).to have_http_status(:created)
      expect(storefront_inbox).to have_attributes(name: 'Made By Hand')
    end
  end
end
