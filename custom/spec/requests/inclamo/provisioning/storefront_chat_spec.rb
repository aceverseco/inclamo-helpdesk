# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App storefront chat: the store has its storefront inbox', type: :request do
  include_context 'with app provisioning'

  let(:store) { ProvisioningRequests::STORE }
  let(:answer) { response.parsed_body }

  def website_inboxes(account)
    account.inboxes.where(channel_type: 'Channel::WebWidget')
  end

  def nothing_created
    not_change(Inbox, :count).and not_change(Channel::WebWidget, :count).and not_change(InboxMember, :count)
  end

  describe 'an account without a storefront inbox' do
    let!(:account) { linked_account(name: 'Maple & Oak') }
    let!(:administrators) { create_list(:user, 2, account: account, role: :administrator) }
    let!(:agent) { create(:user, account: account, role: :agent) }

    it 'creates the inbox with the given address and answers as the contract says' do
      expect { ask_for_chat(with: { storefront_url: 'https://maple-and-oak.example' }) }
        .to change { website_inboxes(account).count }.by(1).and change(Inbox, :count).by(1)

      inbox = storefront_inbox
      expect(response).to have_http_status(:created)
      expect(answer).to eq(
        'contract' => 1, 'inbox_id' => inbox.id, 'website_token' => inbox.channel.website_token,
        'widget_base_url' => ProvisioningRequests::HELPDESK_URL, 'state' => 'active', 'outcome' => 'created'
      )
      expect(inbox.channel).to be_a(Channel::WebWidget)
      expect(inbox.channel).to have_attributes(website_url: 'https://maple-and-oak.example', account_id: account.id)
      expect(inbox).to have_attributes(name: 'Maple & Oak', account_id: account.id)
    end

    it 'uses the store\'s own Shopify address when none is given' do
      ask_for_chat

      expect(response).to have_http_status(:created)
      expect(storefront_inbox.channel.website_url).to eq("https://#{store}")
    end

    it 'treats an address given as null as not given' do
      ask_for_chat(with: { storefront_url: nil })

      expect(response).to have_http_status(:created)
      expect(storefront_inbox.channel.website_url).to eq("https://#{store}")
    end

    it 'names the inbox after the account as the team named it' do
      account.update!(name: 'Renamed By The Team')

      ask_for_chat

      expect(storefront_inbox.name).to eq('Renamed By The Team')
    end

    it 'makes an inbox with Chatwoot\'s defaults: the one Chatwoot\'s own inbox form makes' do
      post "/api/v1/accounts/#{account.id}/inboxes", headers: administrators.first.create_new_auth_token, as: :json,
                                                     params: { name: 'Made in the dashboard',
                                                               channel: { type: 'web_widget', website_url: 'https://by-hand.example' } }
      expect(response).to have_http_status(:ok)
      by_hand = account.inboxes.find_by!(name: 'Made in the dashboard')

      ask_for_chat
      made = storefront_inbox

      own = %w[id name channel_id created_at updated_at]
      expect(made.attributes.except(*own)).to eq(by_hand.attributes.except(*own))
      expect(made.channel.attributes.except('id', 'website_url', 'website_token', 'hmac_token', 'created_at', 'updated_at'))
        .to eq(by_hand.channel.attributes.except('id', 'website_url', 'website_token', 'hmac_token', 'created_at', 'updated_at'))
      expect(made.channel).to have_attributes(widget_color: '#1f93ff', welcome_title: nil, welcome_tagline: nil,
                                              pre_chat_form_enabled: false, hmac_mandatory: false, allowed_domains: '')
      expect(made).to have_attributes(greeting_enabled: false, greeting_message: nil, working_hours_enabled: false)
      expect(made.channel.website_token).to be_present
      expect(made.channel.hmac_token).to be_present
    end

    it 'makes every administrator of the account a member, and nobody else' do
      ask_for_chat

      expect(storefront_inbox.members).to match_array(administrators)
      expect(storefront_inbox.members).not_to include(agent)
    end

    it 'attaches no agent bot, also when the account has one' do
      bot = create(:agent_bot, account: account)

      expect { ask_for_chat }.to not_change(AgentBotInbox, :count)

      expect(storefront_inbox.reload.agent_bot).to be_nil
      expect(bot.reload.inboxes).to be_empty
    end

    it 'leaves the allowed domains empty, so the widget frame is served to any page' do
      ask_for_chat

      expect(storefront_inbox.channel.allowed_domains).to be_blank
      expect_widget_page_served(answer['website_token'])
      expect(response.headers).not_to have_key('X-Frame-Options')
      expect(response.headers['Content-Security-Policy'].to_s).not_to include('frame-ancestors')
    end

    it 'is usable at once: a visitor of the widget opens a conversation in it' do
      ask_for_chat
      inbox = storefront_inbox
      contact_inbox = create(:contact_inbox, contact: create(:contact, account: account, email: nil), inbox: inbox)
      token = Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token

      expect do
        post '/api/v1/widget/conversations', headers: { 'X-Auth-Token' => token },
                                             params: { website_token: answer['website_token'], message: { content: 'Do you ship to Canada?' } }, as: :json
      end.to change { inbox.conversations.count }.by(1)

      expect(response).to have_http_status(:ok)
      conversation = inbox.conversations.last
      expect(conversation.messages.incoming.pluck(:content)).to eq(['Do you ship to Canada?'])
      # No bot holds it: the conversation is the team's.
      expect(conversation).to be_open
    end

    it 'answers the same request id once, with the same answer' do
      request_id = SecureRandom.uuid
      ask_for_chat(request_id: request_id)
      first = response.body

      expect { ask_for_chat(request_id: request_id) }.to nothing_created
      expect(response).to have_http_status(:created)
      expect(response.body).to eq(first)
    end
  end

  describe 'the request body' do
    let!(:account) { linked_account }

    def expect_refused(code)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(answer['error']).to eq(code)
      expect(answer['message']).to be_present
      expect(answer.keys).to contain_exactly('error', 'message')
      expect(storefront_inbox).to be_nil
    end

    it 'refuses a storefront address that is not HTTPS' do
      ['http://maple-and-oak.example', 'ftp://maple-and-oak.example', 'shopify://maple-and-oak.example',
       'javascript:alert(1)'].each do |address|
        expect { ask_for_chat(with: { storefront_url: address }) }.to nothing_created
        expect_refused('storefront_url_invalid')
      end
    end

    it 'refuses a storefront address that is not absolute' do
      ['maple-and-oak.example', '//maple-and-oak.example', '/collections/all', 'https://', 'https:///collections', 'https://maple and oak.example',
       '', '   ', 42, true, ['https://maple-and-oak.example'], { 'href' => 'https://maple-and-oak.example' },
       "https://maple-and-oak.example/#{'a' * 2100}"].each do |address|
        expect { ask_for_chat(with: { storefront_url: address }) }.to nothing_created
        expect_refused('storefront_url_invalid')
      end
    end

    it 'refuses a contract it does not speak, and a body that is not a JSON object' do
      [{ contract: 2 }, { contract: '1' }, { storefront_url: 'https://maple-and-oak.example' }, '', 'contract=1', '[1]', 'null'].each do |body|
        expect { ask_for_chat(body: body) }.to nothing_created
        expect_refused('contract_unsupported')
      end
    end

    it 'accepts a body without a storefront address' do
      ask_for_chat(body: '{"contract":1}')

      expect(response).to have_http_status(:created)
      expect(storefront_inbox).to be_present
    end

    it 'keeps only the origin of a longer address' do
      ask_for_chat(with: { storefront_url: ' HTTPS://staff:secret@Maple-And-Oak.Example:443/collections/all?sort=price#top ' })

      expect(response).to have_http_status(:created)
      expect(storefront_inbox.channel.website_url).to eq('https://maple-and-oak.example')
    end

    it 'keeps a port that is not the usual one' do
      ask_for_chat(with: { storefront_url: 'https://maple-and-oak.example:8443/en' })

      expect(storefront_inbox.channel.website_url).to eq('https://maple-and-oak.example:8443')
    end

    it 'ignores fields it does not know' do
      ask_for_chat(with: { storefront_url: 'https://maple-and-oak.example', widget_color: '#000000', name: 'Another name' })

      expect(response).to have_http_status(:created)
      expect(storefront_inbox).to have_attributes(name: account.name)
      expect(storefront_inbox.channel.widget_color).to eq('#1f93ff')
    end
  end

  describe 'an account that has its storefront inbox' do
    before { provision }

    let(:account) { provisioned.account }
    let(:inbox) { storefront_inbox }

    it 'answers with the same inbox and token, and creates nothing' do
      token = inbox.channel.website_token

      2.times do
        expect { ask_for_chat }.to nothing_created
        expect(response).to have_http_status(:ok)
        expect(answer).to eq(
          'contract' => 1, 'inbox_id' => inbox.id, 'website_token' => token,
          'widget_base_url' => ProvisioningRequests::HELPDESK_URL, 'state' => 'active', 'outcome' => 'existed'
        )
      end
      expect(website_inboxes(account).count).to eq(1)
    end

    it 'changes nothing of an inbox the team renamed, greeted from and readdressed' do
      token = inbox.channel.website_token
      inbox.update!(name: 'Chat with the workshop', greeting_enabled: true, greeting_message: 'Hello from the workshop')
      inbox.channel.update!(website_url: 'https://workshop.example', welcome_title: 'The workshop', widget_color: '#0f766e')
      inbox.add_members([create(:user, account: account, role: :agent).id])

      expect { ask_for_chat(with: { storefront_url: 'https://another-address.example' }) }
        .to nothing_created.and(not_change { inbox.reload.updated_at }).and(not_change { inbox.channel.reload.updated_at })

      expect(response).to have_http_status(:ok)
      expect(answer).to include('outcome' => 'existed', 'website_token' => token, 'inbox_id' => inbox.id)
      expect(inbox.reload).to have_attributes(name: 'Chat with the workshop', greeting_enabled: true, greeting_message: 'Hello from the workshop')
      expect(inbox.channel.reload).to have_attributes(website_url: 'https://workshop.example', welcome_title: 'The workshop',
                                                      widget_color: '#0f766e', website_token: token)
      expect(inbox.members.count).to eq(2)
    end

    it 'does not add a later administrator to the inbox' do
      create(:user, account: account, role: :administrator)

      expect { ask_for_chat }.to not_change { inbox.members.count }
    end

    it 'still validates the body, and changes nothing for one it refuses' do
      ask_for_chat(with: { storefront_url: 'http://another-address.example' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(answer['error']).to eq('storefront_url_invalid')
      expect(inbox.channel.reload.website_url).to eq("https://#{store}")
    end

    it 'finds the store whatever the case of the domain' do
      ask_for_chat('Example-Store.MyShopify.com')

      expect(response).to have_http_status(:ok)
      expect(answer).to include('outcome' => 'existed', 'inbox_id' => inbox.id)
    end
  end

  describe 'website inboxes the team made themselves' do
    let!(:account) { linked_account }
    let!(:own) { create(:channel_widget, account: account, website_url: 'https://another-site.example').inbox }

    it 'are not reported: the account has no storefront inbox' do
      ask_chat_status

      expect(response).to have_http_status(:not_found)
      expect(answer).to eq('error' => 'no_storefront_chat')
    end

    it 'are left alone: a separate storefront inbox is created and theirs is in no answer' do
      own_token = own.channel.website_token

      expect { ask_for_chat }
        .to change { website_inboxes(account).count }.from(1).to(2)
        .and(not_change { own.reload.attributes }).and(not_change { own.channel.reload.attributes })

      expect(response).to have_http_status(:created)
      expect(storefront_inbox).not_to eq(own)
      expect(answer['inbox_id']).to eq(storefront_inbox.id)
      expect(answer['website_token']).not_to eq(own_token)
      bodies = [response.body]
      ask_for_chat
      bodies << response.body
      ask_chat_status
      bodies << response.body
      expect(bodies.join).not_to include(own_token)
      expect(bodies.join).not_to include(own.channel.hmac_token)
      expect(website_inboxes(account).count).to eq(2)
    end

    it 'are not adopted when the storefront inbox is deleted' do
      ask_for_chat
      storefront_inbox.destroy!

      ask_chat_status

      expect(answer).to eq('error' => 'no_storefront_chat')
      expect(own.reload).to be_present
    end
  end

  describe 'the status call' do
    it 'tells of an active account\'s storefront inbox, the public values and nothing else' do
      provision
      inbox = storefront_inbox
      create_list(:conversation, 2, account: inbox.account, inbox: inbox)

      expect { ask_chat_status }.to nothing_created.and not_change(Inclamo::ProvisioningEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(answer).to eq(
        'contract' => 1, 'inbox_id' => inbox.id, 'website_token' => inbox.channel.website_token,
        'widget_base_url' => ProvisioningRequests::HELPDESK_URL, 'state' => 'active'
      )
      expect(response.body).not_to include(inbox.channel.hmac_token)
      expect(answer.except('website_token').to_json).not_to match(/hmac|alex|member|user|conversation|contact|greeting|color|name|outcome/i)
    end

    it 'holds no identity-verification key, setting, conversation, contact or member in the answer that creates either' do
      account = linked_account
      create(:user, account: account, role: :administrator, name: 'Morgan Example', email: 'morgan@example.test')

      ask_for_chat

      expect(answer.keys).to contain_exactly('contract', 'inbox_id', 'website_token', 'widget_base_url', 'state', 'outcome')
      expect(response.body).not_to include(storefront_inbox.channel.hmac_token)
      expect(answer.except('website_token').to_json).not_to match(/hmac|morgan|member|user|conversation|contact|greeting|color|name/i)
    end

    it 'tells of a suspended account, with the inbox and its token kept' do
      provision
      token = storefront_inbox.channel.website_token
      remove_app

      ask_chat_status

      expect(response).to have_http_status(:ok)
      expect(answer).to eq(
        'contract' => 1, 'inbox_id' => storefront_inbox.id, 'website_token' => token,
        'widget_base_url' => ProvisioningRequests::HELPDESK_URL, 'state' => 'suspended'
      )
    end

    it 'tells of an account the operator suspended by hand as suspended' do
      provision
      provisioned.account.update!(status: :suspended)

      ask_chat_status

      expect(answer['state']).to eq('suspended')
    end

    it 'says there is none for an account without a storefront inbox' do
      linked_account

      expect { ask_chat_status }.to nothing_created

      expect(response).to have_http_status(:not_found)
      expect(answer).to eq('error' => 'no_storefront_chat')
    end

    it 'says there is no account for a store that has none, and creates nothing' do
      ['unknown-store.myshopify.com', 'shop.example.com'].each do |domain|
        expect { ask_chat_status(domain) }
          .to nothing_created.and not_change(Account, :count).and not_change(Inclamo::ProvisionedAccount, :count)
        expect(response).to have_http_status(:not_found)
        expect(answer).to eq('error' => 'no_account')
      end
    end
  end

  describe 'a store without an account' do
    it 'is answered that there is no account, and nothing is created' do
      ['unknown-store.myshopify.com', 'shop.example.com'].each do |domain|
        expect { ask_for_chat(domain, with: { storefront_url: 'https://unknown.example' }) }
          .to nothing_created.and not_change(Account, :count).and not_change(Inclamo::ProvisionedAccount, :count)
        expect(response).to have_http_status(:not_found)
        expect(answer).to eq('error' => 'no_account')
      end
    end
  end

  describe 'a suspended account' do
    it 'is refused as not active, and nothing is created' do
      account = linked_account
      remove_app

      expect { ask_for_chat(with: { storefront_url: 'https://maple-and-oak.example' }) }.to nothing_created

      expect(response).to have_http_status(:conflict)
      expect(answer).to eq('error' => 'account_suspended')
      expect(storefront_inbox).to be_nil
      expect(account.reload.inboxes).to be_empty
    end

    it 'is refused also when it has its storefront inbox, which is kept' do
      provision
      inbox = storefront_inbox
      remove_app

      expect { ask_for_chat }.to nothing_created

      expect(response).to have_http_status(:conflict)
      expect(answer).to eq('error' => 'account_suspended')
      expect(storefront_inbox).to eq(inbox)
    end

    it 'is refused when the operator suspended the account by hand' do
      linked_account.update!(status: :suspended)

      expect { ask_for_chat }.to nothing_created
      expect(response).to have_http_status(:conflict)
    end

    it 'gets its inbox once it is restored and the app asks' do
      linked_account
      remove_app
      provision
      expect(response.parsed_body['outcome']).to eq('restored')
      expect(storefront_inbox).to be_nil

      ask_for_chat

      expect(response).to have_http_status(:created)
      expect(storefront_inbox.members).to include(User.from_email('alex@example.test'))
    end
  end

  describe 'the team deletes the storefront inbox' do
    before { provision }

    let(:account) { provisioned.account }
    let(:administrator) { User.from_email('alex@example.test') }

    def delete_in_the_dashboard(inbox)
      perform_enqueued_jobs do
        delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:ok)
    end

    it 'reports none once Chatwoot\'s delete job has run, and the old token is not found' do
      inbox = storefront_inbox
      old_token = inbox.channel.website_token
      create(:conversation, account: account, inbox: inbox)

      delete_in_the_dashboard(inbox)

      expect(Inbox.exists?(inbox.id)).to be(false)
      expect(provisioned).to have_attributes(storefront_inbox_id: nil, account_id: account.id, state: 'active')
      ask_chat_status
      expect(response).to have_http_status(:not_found)
      expect(answer).to eq('error' => 'no_storefront_chat')
      get '/widget', params: { website_token: old_token }
      expect(response).to have_http_status(:not_found)
      post '/api/v1/widget/conversations', params: { website_token: old_token, message: { content: 'Hello' } }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'still reports the inbox between the click and the job' do
      inbox = storefront_inbox

      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      ask_chat_status

      expect(response).to have_http_status(:ok)
      expect(answer['inbox_id']).to eq(inbox.id)
    end

    it 'makes no new inbox by itself: not on a status call and not on the account\'s own call' do
      delete_in_the_dashboard(storefront_inbox)

      expect do
        ask_chat_status
        provision
        ask_status
      end.to nothing_created
      expect(storefront_inbox).to be_nil
    end

    it 'makes a new inbox with another token and none of the earlier conversations when the app asks again' do
      old = storefront_inbox
      old_token = old.channel.website_token
      create_list(:conversation, 2, account: account, inbox: old)
      delete_in_the_dashboard(old)

      expect { ask_for_chat(with: { storefront_url: 'https://maple-and-oak.example' }) }.to change(Inbox, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(answer).to include('outcome' => 'created', 'state' => 'active')
      expect(answer['website_token']).not_to eq(old_token)
      expect(answer['inbox_id']).not_to eq(old.id)
      expect(storefront_inbox.conversations).to be_empty
      expect(storefront_inbox.channel.website_url).to eq('https://maple-and-oak.example')
      expect(storefront_inbox.members).to contain_exactly(administrator)
      expect_widget_page_served(answer['website_token'])
    end
  end
end
