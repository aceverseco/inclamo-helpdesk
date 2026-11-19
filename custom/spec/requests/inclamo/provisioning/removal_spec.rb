# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: removal, suspension and restoration', type: :request do
  include_context 'with app provisioning'

  let(:account) { provisioned.account }
  let(:administrator) { User.from_email('alex@example.test') }
  let(:inbox) { create(:inbox, account: account) }

  before { provision }

  def open_account(user, target = account)
    get "/api/v1/accounts/#{target.id}/conversations", headers: user.create_new_auth_token, as: :json
    response
  end

  def fill(count)
    create_list(:conversation, count, account: account, inbox: inbox)
  end

  describe 'the app is removed' do
    it 'suspends the account and keeps its conversations, contacts and settings' do
      conversations = fill(3)
      label = create(:label, account: account)
      account.update!(name: 'Renamed By The Team')
      queues = Inclamo::TeamQueue.where(account_id: account.id).count

      expect { remove_app }
        .to not_change { account.conversations.count }.and not_change { account.contacts.count }
        .and not_change { account.messages.count }.and not_change { account.users.count }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'suspended')
      expect(account.reload).to be_suspended
      expect(provisioned).to be_suspended
      expect(account).to have_attributes(name: 'Renamed By The Team', locale: 'fr')
      expect(Conversation.where(id: conversations.map(&:id)).count).to eq(3)
      expect(account.inboxes).to include(inbox)
      expect(account.labels).to include(label)
      expect(Inclamo::TeamQueue.where(account_id: account.id).count).to eq(queues)
      expect(administrator.account_users.find_by(account_id: account.id)).to be_administrator
    end

    it 'answers a repeated notice as done, with the account still suspended and whole' do
      fill(2)
      remove_app

      expect { remove_app }.to not_change { account.conversations.count }.and(not_change { account.reload.updated_at })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'suspended')
      expect(account.reload).to be_suspended
    end

    it 'answers a notice for a store without an account as done' do
      expect { remove_app('unknown-store.myshopify.com') }.to not_change(Inclamo::ProvisionedAccount, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none')
      expect(account.reload).to be_active

      remove_app('shop.example.com')
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none')
    end

    it 'suspends the store whatever the case of the domain' do
      remove_app('Example-Store.MyShopify.com')

      expect(response.parsed_body['state']).to eq('suspended')
      expect(account.reload).to be_suspended
    end
  end

  describe 'what suspension means' do
    it 'has the dashboard API refuse the account\'s administrator' do
      expect(open_account(administrator)).to have_http_status(:ok)

      remove_app

      expect(open_account(administrator)).to have_http_status(:unauthorized)
      expect(response.body).to include('Account is suspended')
    end

    it 'has the widget refuse a new conversation' do
      widget = create(:channel_widget, account: account)
      contact_inbox = create(:contact_inbox, contact: create(:contact, account: account, email: nil), inbox: widget.inbox)
      token = Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: widget.inbox.id }).generate_token
      start = lambda do
        post '/api/v1/widget/conversations', headers: { 'X-Auth-Token' => token },
                                             params: { website_token: widget.website_token, message: { content: 'Hello' } }, as: :json
      end

      remove_app
      expect { start.call }.to not_change(Conversation, :count).and not_change(Message, :count)
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('Account is suspended')

      get '/widget', params: { website_token: widget.website_token }
      expect(response).to have_http_status(:unauthorized)

      provision
      expect { start.call }.to change { widget.inbox.conversations.count }.by(1)
      expect(response).to have_http_status(:ok)
    end

    it 'still lets a user of two accounts open the other one' do
      provision('second-store.myshopify.com')
      other = provisioned('second-store.myshopify.com').account
      expect(administrator.accounts).to contain_exactly(account, other)

      remove_app

      expect(open_account(administrator)).to have_http_status(:unauthorized)
      expect(open_account(administrator, other)).to have_http_status(:ok)
      expect(other.reload).to be_active
    end
  end

  describe 'the store installs the app again' do
    it 'restores the same account with its earlier conversations' do
      conversations = fill(12)
      remove_app

      administrator.update_columns(sign_in_count: 1)

      expect { provision }.to not_change(Account, :count).and not_change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'contract' => 1, 'account_id' => account.id, 'helpdesk_url' => ProvisioningRequests::HELPDESK_URL,
        'state' => 'active', 'outcome' => 'restored', 'created_at' => account.created_at.utc.iso8601, 'admin_is_member' => true
      )
      expect(account.reload).to be_active
      expect(provisioned).to be_active

      expect(open_account(administrator)).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'meta', 'all_count')).to eq(12)
      expect(account.conversations.pluck(:id)).to match_array(conversations.map(&:id))
    end

    it 'does not change the name the team gave the account' do
      account.update!(name: 'Renamed By The Team')
      remove_app

      provision(shop: { name: 'Example Store Ltd', locale: 'de' })

      expect(account.reload).to have_attributes(name: 'Renamed By The Team', locale: 'fr')
    end

    it 'makes a person who was never its user an administrator next to the earlier ones' do
      earlier_agent = create(:user, account: account, role: :agent)
      remove_app

      expect { provision(admin: { email: 'sam@example.test', name: 'Sam Example' }) }.to change(User, :count).by(1)

      expect(response.parsed_body['outcome']).to eq('restored')
      sam = User.from_email('sam@example.test')
      expect(sam).to be_confirmed
      expect(account.reload.administrators).to contain_exactly(administrator, sam)
      expect(account.agents).to contain_exactly(earlier_agent)
      expect(open_account(sam)).to have_http_status(:ok)
      expect(open_account(administrator)).to have_http_status(:ok)
    end

    def set_password(url, password)
      token = Rack::Utils.parse_query(URI(url).query).fetch('reset_password_token')
      put '/auth/password', params: { reset_password_token: token, password: password, password_confirmation: password }, as: :json
      response
    end

    it 'gives the password link to a person it created, and none to one who has signed in' do
      remove_app
      provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
      expect(response.parsed_body).to include('outcome' => 'restored', 'admin_is_member' => true)
      expect(set_password(response.parsed_body.fetch('password_setup_url'), 'OwnPassword1!')).to have_http_status(:ok)
      expect(User.from_email('sam@example.test').valid_password?('OwnPassword1!')).to be(true)

      remove_app
      provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
      expect(response.parsed_body).to include('outcome' => 'restored', 'admin_is_member' => true)
      expect(response.parsed_body).not_to have_key('password_setup_url')
    end

    it 'gives a new link to a user of the account who never signed in, and the earlier one stops working' do
      first = response.parsed_body.fetch('password_setup_url')
      remove_app

      provision

      expect(response.parsed_body).to include('outcome' => 'restored', 'admin_is_member' => true)
      fresh = response.parsed_body.fetch('password_setup_url')
      expect(set_password(first, 'OwnPassword1!')).to have_http_status(:unprocessable_entity)
      expect(set_password(fresh, 'OwnPassword1!')).to have_http_status(:ok)
    end

    it 'makes an earlier agent who installs again an administrator, with their other account as it was' do
      elsewhere = create(:account)
      agent = create(:user, email: 'sam@example.test', password: 'KnownPassword1!', account: elsewhere, role: :agent)
      agent.update_columns(sign_in_count: 3)
      create(:account_user, account: account, user: agent, role: :agent)
      remove_app

      expect { provision(admin: { email: 'sam@example.test', name: 'Sam Example' }) }.to not_change(AccountUser, :count)

      expect(agent.account_users.pluck(:account_id, :role)).to contain_exactly([elsewhere.id, 'agent'], [account.id, 'administrator'])
      expect(agent.reload.valid_password?('KnownPassword1!')).to be(true)
      expect(response.parsed_body).not_to have_key('password_setup_url')
    end
  end
end
