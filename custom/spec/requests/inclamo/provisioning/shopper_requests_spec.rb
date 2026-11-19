# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')

# The store app's requests about one shopper (docs/app-store-erasure.md §4–§6):
# a ticket in the account's "Data requests" inbox, the answers the app gets,
# and the counts of a store's requests.
RSpec.describe 'App store erasure: requests about one shopper', type: :request do
  include_context 'with app provisioning'
  include ShopperRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }

  around { |example| travel_to(now) { example.run } }

  before { active_store }

  describe 'the "Data requests" inbox' do
    let!(:shopper) { shopper_contact(account) }

    it 'is an API inbox without members and without a bot, with one fixed contact and the two labels' do
      ask_shopper_erasure

      inbox = data_requests_inbox(account)
      expect(inbox.channel).to be_a(Channel::Api)
      expect(inbox.name).to eq('Data requests')
      expect(inbox.members).to be_empty
      expect(inbox.agent_bot_inbox).to be_nil
      expect(inbox.enable_auto_assignment).to be(false)
      place = Inclamo::DataRequestInbox.find_by(account_id: account.id)
      expect(place.contact).to have_attributes(name: 'Shopify data requests', email: nil, phone_number: nil)
      expect(account.labels.pluck(:title)).to include('inclamo_erasure_request', 'inclamo_data_request')

      ticket = ticket_of(shopper_request)
      expect(ticket).to have_attributes(inbox_id: inbox.id, contact_id: place.contact_id, status: 'open', priority: 'high')
      expect(ticket.label_list).to eq(['inclamo_erasure_request'])
      expect(ticket.custom_attributes).to eq('inclamo_shopper_request_id' => shopper_request.id)
      expect(ticket.contact_id).not_to eq(shopper.id)
    end

    it 'is made once: a second request makes no second inbox or contact' do
      ask_shopper_erasure
      ask_data_request
      ask_shopper_erasure(shopper: { email: 'kim@example.com' })
      shopper_contact(account, email: 'kim@example.com', phone: '+15550000002', conversations: 1)
      ask_shopper_erasure(shopper: { email: 'kim@example.com' })

      expect(Inclamo::DataRequestInbox.where(account_id: account.id).count).to eq(1)
      expect(account.inboxes.where(name: 'Data requests').count).to eq(1)
      expect(account.contacts.where(name: 'Shopify data requests').count).to eq(1)
      expect(Conversation.where(inbox_id: data_requests_inbox(account).id).count).to eq(3)
    end

    it 'is named in the account\'s language' do
      account.update!(locale: 'uk')

      ask_shopper_erasure

      expect(data_requests_inbox(account).name).to eq('Запити щодо даних')
      expect(ticket_texts(shopper_request).first).to include("\n\nShopify від імені власника магазину")
    end

    it 'shows the ticket to an administrator and not to an agent, even an agent of the shopper\'s inbox' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agent, inbox: shopper.conversations.first.inbox)
      ask_shopper_erasure
      ticket = ticket_of(shopper_request)

      list = lambda do |user|
        get "/api/v1/accounts/#{account.id}/conversations", params: { status: 'all', assignee_type: 'all' }, headers: user.create_new_auth_token
        response.parsed_body.dig('data', 'payload').pluck('id')
      end

      expect(list.call(store_administrator)).to include(ticket.display_id)
      expect(list.call(agent)).not_to include(ticket.display_id)
      expect(list.call(agent)).to include(*shopper.conversations.pluck(:display_id))
      get "/api/v1/accounts/#{account.id}/conversations/#{ticket.display_id}", headers: agent.create_new_auth_token
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'Shopify asked to erase one shopper' do
    let!(:shopper) { shopper_contact(account) }

    it 'makes a ticket naming the contacts and conversations found and the date, and deletes nothing' do
      expect { ask_shopper_erasure(order_ids: %w[299938 280263]) }
        .to not_change(Contact.where(id: shopper.id), :count).and not_change(shopper.conversations, :count)

      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'waiting', 'contacts' => 1, 'conversations' => 2,
                                         'delete_after' => '2026-12-04T10:00:00Z')
      expect(shopper_request).to have_attributes(
        state: 'waiting', account_id: account.id, received_at: now, delete_after: now + 14.days, email: 'pat@example.com',
        phone: '+15556251199', order_ids: %w[299938 280263]
      )
      note = Message.find_by(conversation_id: shopper_request.conversation_id)
      expect(note).to have_attributes(private: true, message_type: 'outgoing')
      expect(note.content).to include('1 contact and 2 conversations', '2026-12-04 10:00 UTC')
      expect(note.content).not_to include('pat@example.com')
      expect(note.content).not_to include('5556251199')
      expect(events_of.last).to eq('shopper_ticket_made')
    end

    it 'takes the waiting time the operator set, in whole days from 1 to 25, and the default otherwise' do
      { '1' => 1.day, '25' => 25.days, '20' => 20.days }.each do |days, wait|
        with_modified_env(INCLAMO_SHOPPER_ERASURE_WAIT_DAYS: days) { expect(Inclamo::Erasure.shopper_wait).to eq(wait) }
      end
      %w[0 26 -1 fourteen 1.5].push('').each do |days|
        with_modified_env(INCLAMO_SHOPPER_ERASURE_WAIT_DAYS: days) { expect(Inclamo::Erasure.shopper_wait).to eq(14.days) }
      end
      with_modified_env(INCLAMO_SHOPPER_ERASURE_WAIT_SECONDS: '30', INCLAMO_E2E: nil) { expect(Inclamo::Erasure.shopper_wait).to eq(14.days) }
      with_modified_env(INCLAMO_SHOPPER_ERASURE_WAIT_SECONDS: '30', INCLAMO_E2E: '1') { expect(Inclamo::Erasure.shopper_wait).to eq(30.seconds) }

      with_modified_env(INCLAMO_SHOPPER_ERASURE_WAIT_DAYS: '3') { ask_shopper_erasure }
      expect(response.parsed_body['delete_after']).to eq('2026-11-23T10:00:00Z')
    end

    it 'answers a repetition three days later with the same ticket and date, and moves nothing' do
      ask_shopper_erasure
      first = shopper_request

      travel 3.days
      expect { ask_shopper_erasure }.not_to change(Inclamo::ErasureRequest, :count)

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'waiting', 'contacts' => 1, 'conversations' => 2,
                                         'delete_after' => '2026-12-04T10:00:00Z')
      expect(Conversation.where(inbox_id: data_requests_inbox(account).id).count).to eq(1)
      expect(first.reload.delete_after).to eq(now + 14.days)
      expect(events_of.last).to eq('shopper_ticket_found')
    end

    it 'finds the same shopper by the phone alone, written with spaces and a plus, and the same ticket by the same values' do
      ask_shopper_erasure(shopper: { phone: '+1 555 625 1199' })

      expect(response.parsed_body).to include('state' => 'waiting', 'contacts' => 1)
      expect { ask_shopper_erasure(shopper: { phone: '+1 (555) 625-1199' }) }.not_to change(Inclamo::ErasureRequest, :count)
    end

    it 'answers a held request with its state and when, without its reason or its author' do
      ask_shopper_erasure
      Inclamo::Erasure::ShopperActions.hold!(shopper_request, store_administrator, 'open payment dispute')

      ask_shopper_erasure

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'held', 'held_at' => '2026-11-20T10:00:00Z')
      expect(response.body).not_to include('payment dispute')
      expect(response.body).not_to include('Alex')
    end

    it 'answers done once the data is deleted, and makes a new ticket when the shopper is found again' do
      ask_shopper_erasure
      first = shopper_request
      travel 1.day
      perform_enqueued_jobs { Inclamo::Erasure::ShopperActions.delete!(first, store_administrator) }

      ask_shopper_erasure
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'done', 'done_at' => '2026-11-21T10:00:00Z', 'done_by' => 'team')
      expect(Inclamo::ErasureRequest.shoppers.count).to eq(1)

      shopper_contact(account, conversations: 1)
      ask_shopper_erasure
      expect(response.parsed_body).to include('state' => 'waiting', 'contacts' => 1, 'conversations' => 1)
      expect(shopper_request.id).not_to eq(first.id)
      expect(Conversation.where(inbox_id: data_requests_inbox(account).id).count).to eq(2)
    end

    it 'answers that nothing is held for a shopper the account does not know, and makes nothing' do
      expect { ask_shopper_erasure(shopper: { email: 'nobody@example.com', phone: '+15550009999' }) }
        .to not_change(Conversation, :count).and not_change(Inclamo::ErasureRequest, :count)

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none', 'contacts' => 0)
      expect(Inclamo::DataRequestInbox.count).to eq(0)
      expect(events_of.last).to eq('shopper_none')
    end

    it 'does not count or touch the same email in another store\'s account' do
      provision('other-store.myshopify.com', admin: { email: 'sam@example.test' })
      other = provisioned('other-store.myshopify.com').account
      theirs = shopper_contact(other, conversations: 3)

      ask_shopper_erasure

      expect(response.parsed_body).to include('contacts' => 1, 'conversations' => 2)
      expect(Inclamo::DataRequestInbox.where(account_id: other.id)).to be_empty
      expect(other.conversations.count).to eq(3)
      expect(theirs.reload).to be_present
    end

    it 'answers a store without an account as a shopper nothing is held of' do
      ask_shopper_erasure('never-installed.myshopify.com')

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none', 'contacts' => 0)
    end

    it 'makes a ticket in a suspended account too' do
      remove_app

      ask_shopper_erasure

      expect(response.parsed_body).to include('state' => 'waiting', 'contacts' => 1)
      expect(ticket_of(shopper_request).account_id).to eq(account.id)
    end

    it 'refuses a request naming neither an email nor a phone, or another contract, and makes nothing' do
      [{ contract: 1, shopper: {} }, { contract: 1, shopper: { email: ' ', phone: '' } }, { contract: 1, shopper: { phone: 'none' } },
       { contract: 1 }, { contract: 1, shopper: 'pat@example.com' }].each do |body|
        ask_shopper_erasure(body: body)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('shopper_missing')
      end
      ['{"contract":2,"shopper":{"email":"pat@example.com"}}', 'not json', '[]'].each do |body|
        ask_shopper_erasure(body: body)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('contract_unsupported')
      end
      expect(response.body).not_to include('pat@example.com')
      expect(Inclamo::ErasureRequest.count).to eq(0)
      expect(events_of.uniq).to eq(%w[created refused])
    end
  end

  describe 'a shopper asked for their data' do
    let!(:shopper) { shopper_contact(account, conversations: 3, name: 'Pat Example', additional_attributes: { city: 'Springfield' }) }

    it 'makes a ticket linking the contacts, answers with numbers only, and deletes nothing' do
      Message.create!(account: account, inbox: shopper.conversations.first.inbox, conversation: shopper.conversations.first,
                      message_type: :incoming, content: 'my order to 1 Example Street', sender: shopper)

      expect { ask_data_request(order_ids: ['299938']) }
        .to not_change(Contact.where(id: shopper.id), :count).and not_change(Message.where(sender: shopper), :count)
        .and not_change(shopper.conversations, :count)

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'waiting', 'contacts' => 1, 'conversations' => 3, 'account_state' => 'active')
      %w[Pat pat@example.com 5556251199 Springfield Example\ Street /contacts/].each do |text|
        expect(response.body).not_to include(text)
      end
      request = shopper_request('shopper_data_request')
      expect(request).to have_attributes(state: 'waiting', delete_after: nil, email: 'pat@example.com')
      expect(ticket_of(request).label_list).to eq(['inclamo_data_request'])
      note = ticket_texts(request).first
      expect(note).to include('copy of their data', '1 contact and 3 conversations')
      expect(note).not_to include('pat@example.com')
      expect(events_of.last).to eq('data_request_made')
    end

    it 'answers a repetition with the same ticket, and says when the account is suspended' do
      ask_data_request
      remove_app

      expect { ask_data_request }.not_to change(Inclamo::ErasureRequest, :count)

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'waiting', 'contacts' => 1, 'conversations' => 3, 'account_state' => 'suspended')
      expect(events_of.last).to eq('data_request_found')
    end

    it 'answers done once the team marked it answered' do
      ask_data_request
      Inclamo::Erasure::ShopperActions.answered!(shopper_request('shopper_data_request'), store_administrator)
      shopper.destroy!

      ask_data_request

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'done', 'contacts' => 0, 'conversations' => 0, 'account_state' => 'active')
    end

    it 'answers that nothing is held for an unknown shopper, and makes no ticket' do
      expect { ask_data_request(shopper: { email: 'nobody@example.com' }) }.not_to change(Conversation, :count)

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none', 'contacts' => 0, 'conversations' => 0)
      expect(events_of.last).to eq('data_request_none')
    end
  end

  describe 'how many requests wait' do
    it 'counts waiting, held and overdue requests of the store, overdue among the others, and names no shopper' do
      shopper_contact(account, email: 'one@example.com', phone: '+15550000001')
      shopper_contact(account, email: 'two@example.com', phone: '+15550000002')
      shopper_contact(account, email: 'three@example.com', phone: '+15550000003')
      ask_data_request(shopper: { email: 'three@example.com' })
      travel 31.days
      ask_shopper_erasure(shopper: { email: 'one@example.com' })
      ask_shopper_erasure(shopper: { email: 'two@example.com' })
      Inclamo::Erasure::ShopperActions.hold!(shopper_request, store_administrator, 'open payment dispute')

      ask_shopper_counts

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'contract' => 1, 'erasures' => { 'waiting' => 1, 'held' => 1, 'overdue' => 0 },
        'data_requests' => { 'waiting' => 1, 'overdue' => 1 }, 'account_state' => 'active'
      )
      %w[one@ two@ three@ 555000 payment Alex].each { |text| expect(response.body).not_to include(text) }

      # A month on, the waiting one was deleted by the daily run; the held one
      # is overdue.
      travel 30.days
      run_erasures
      ask_shopper_counts
      expect(response.parsed_body['erasures']).to eq('waiting' => 0, 'held' => 1, 'overdue' => 1)
    end

    it 'answers no_account for a store without an account' do
      ask_shopper_counts('never-installed.myshopify.com')

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')
      expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
    end
  end

  describe 'the request log' do
    it 'holds neither the email nor the phone of either call' do
      shopper_contact(account)
      log = StringIO.new
      capture = ActiveSupport::Logger.new(log, level: :info)
      loggers = [Rails, ActionController::Base, ActionController::API]
      originals = loggers.map(&:logger)
      begin
        loggers.each { |owner| owner.logger = capture }
        ask_shopper_erasure(shopper: { email: 'Pat@Example.com', phone: '+1 555 625 1199' })
        ask_data_request(shopper: { email: 'Pat@Example.com', phone: '+1 555 625 1199' })
      ensure
        loggers.zip(originals).each { |owner, original| owner.logger = original }
      end

      expect(log.string).to include('/shoppers/erasure', '/shoppers/data-request')
      expect(log.string.downcase).not_to include('pat@example.com')
      expect(log.string).not_to include('555 625 1199')
      filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                              .filter('shopper' => { 'email' => 'pat@example.com', 'phone' => '+15556251199' })
      expect(filtered).to eq('shopper' => { 'email' => '[FILTERED]', 'phone' => '[FILTERED]' })
    end
  end
end
