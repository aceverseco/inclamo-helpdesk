# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/erasure_requests')

# The store's erasure is scheduled, not immediate (docs/app-store-erasure.md
# §3.2, §3.3): its answers, its waiting time, what cancels it and what does not.
RSpec.describe 'App store erasure: scheduling and cancelling', type: :request do
  include_context 'with app provisioning'
  include ErasureRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }

  around { |example| travel_to(now) { example.run } }

  describe 'a suspended account' do
    before do
      suspended_store
      create_list(:conversation, 2, account: account, inbox: create(:inbox, account: account))
    end

    it 'is scheduled for the end of the waiting time, and is kept whole until then' do
      expect { ask_erasure }.to not_change(Conversation, :count).and not_change(Contact, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'scheduled', 'erase_after' => '2026-11-27T10:00:00Z')
      expect(response.headers['X-Inclamo-Provisioning']).to eq('1')
      expect(provisioned).to have_attributes(state: 'suspended', account_id: account.id, erase_after: now + 7.days)
      expect(account.reload).to be_suspended
      expect(account.conversations.count).to eq(2)
      expect(store_record).to have_attributes(kind: 'store', state: 'scheduled', account_id: account.id, received_at: now, completed_at: nil)
      expect(events_of.last).to eq('erasure_scheduled')
    end

    it 'answers a repetition two days later with the same time, and moves nothing' do
      ask_erasure

      travel 2.days
      expect { ask_erasure }.not_to change(Inclamo::ErasureRequest, :count)

      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'scheduled', 'erase_after' => '2026-11-27T10:00:00Z')
      expect(provisioned.erase_after).to eq(now + 7.days)
      expect(store_record.received_at).to eq(now)
    end

    it 'takes the waiting time the operator set, in whole days from 0 to 21, and the default otherwise' do
      { '0' => now, '21' => now + 21.days, '14' => now + 14.days }.each do |days, time|
        with_modified_env(INCLAMO_ERASURE_WAIT_DAYS: days) { expect(Inclamo::Erasure.store_wait.from_now).to eq(time) }
      end
      %w[22 -1 seven 1.5].push('').each do |days|
        with_modified_env(INCLAMO_ERASURE_WAIT_DAYS: days) { expect(Inclamo::Erasure.store_wait).to eq(7.days) }
      end

      with_modified_env(INCLAMO_ERASURE_WAIT_DAYS: '3') { ask_erasure }
      expect(response.parsed_body['erase_after']).to eq('2026-11-23T10:00:00Z')
    end

    it 'counts in seconds only in the end-to-end stack' do
      with_modified_env(INCLAMO_ERASURE_WAIT_SECONDS: '30', INCLAMO_E2E: nil) { expect(Inclamo::Erasure.store_wait).to eq(7.days) }
      with_modified_env(INCLAMO_ERASURE_WAIT_SECONDS: '30', INCLAMO_E2E: '1') { expect(Inclamo::Erasure.store_wait).to eq(30.seconds) }
    end

    it 'answers that the account is being destroyed, and then that it is erased, with the time' do
      ask_erasure
      travel_to(now + 7.days + 1.minute)
      Inclamo::Erasure::Store.begin!(provisioned)

      ask_erasure
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'erasing')
      expect(events_of.last).to eq('erasing')

      run_erasures_now
      ask_erasure
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'erased', 'erased_at' => (now + 7.days + 1.minute).utc.iso8601)
      expect(events_of.last).to eq('erased')
    end

    it 'refuses a body that states no contract it speaks, and schedules nothing' do
      ['{"contract":2}', '', '[]', 'not json'].each do |body|
        ask_erasure(body: body)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'contract_unsupported')
      end
      expect(provisioned.erase_after).to be_nil
      expect(Inclamo::ErasureRequest.count).to eq(0)
    end

    def run_erasures_now
      perform_enqueued_jobs { Inclamo::StoreErasureJob.perform_now(store_record.id) }
    end
  end

  describe 'an active account' do
    before { provision }

    it 'is refused: the store installed the app again before the request arrived' do
      ask_erasure

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'account_active')
      expect(provisioned).to have_attributes(state: 'active', erase_after: nil)
      expect(Inclamo::ErasureRequest.count).to eq(0)
      expect(events_of.last).to eq('refused')
    end

    it 'is refused while the operator keeps the account active, even with the store removed' do
      remove_app
      account.update!(status: :active)

      ask_erasure

      expect(response.parsed_body).to eq('error' => 'account_active')
      expect(provisioned.erase_after).to be_nil
    end
  end

  describe 'a store without an account' do
    it 'answers that there is nothing to erase, and records nothing as scheduled' do
      %w[unknown-store.myshopify.com shop.example.com].each do |domain|
        expect { ask_erasure(domain) }.not_to change(Inclamo::ErasureRequest, :count)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none')
      end
      expect(Inclamo::ProvisionedAccount.count).to eq(0)
      expect(events_of('unknown-store.myshopify.com')).to eq(['none'])
    end
  end

  describe 'a reinstall inside the waiting time' do
    before do
      suspended_store
      create_list(:conversation, 3, account: account, inbox: create(:inbox, account: account))
      ask_erasure
    end

    it 'withdraws the erasure: the account survives the run after the old time, with everything it held' do
      travel 3.days
      provision

      expect(response.parsed_body).to include('outcome' => 'restored', 'account_id' => account.id)
      expect(provisioned).to have_attributes(state: 'active', erase_after: nil)
      expect(store_record).to have_attributes(state: 'cancelled', completed_at: now + 3.days)
      expect(events_of.last(2)).to eq(%w[erasure_cancelled restored])
      expect(Inclamo::ProvisioningEvent.where(outcome: 'erasure_cancelled').sole.request_id).to be_present

      travel 10.days
      expect { run_erasures }.not_to change(Conversation, :count)
      expect(account.reload).to be_active
      expect(account.conversations.count).to eq(3)
      expect(provisioned).to have_attributes(state: 'active', account_id: account.id)
    end

    it 'is not erased later unless a new request arrives after it is suspended again' do
      provision
      remove_app

      travel 10.days
      run_erasures
      expect(account.reload).to be_suspended
      expect(provisioned).to have_attributes(state: 'suspended', erase_after: nil)

      ask_erasure
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'scheduled', 'erase_after' => '2026-12-07T10:00:00Z')
      expect(Inclamo::ErasureRequest.stores.pluck(:state)).to contain_exactly('cancelled', 'scheduled')
    end
  end

  describe 'installing again after erasure' do
    before do
      suspended_store
      create_list(:conversation, 2, account: account, inbox: create(:inbox, account: account))
      ask_erasure
      travel 8.days
      run_erasures
    end

    it 'creates a new, empty account into the store\'s row' do
      erased_id = store_record.account_id
      expect(provisioned).to have_attributes(state: 'erased', account_id: nil)

      provision

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('outcome' => 'created', 'state' => 'active', 'admin_is_member' => true)
      expect(response.parsed_body['password_setup_url']).to be_present
      new_id = response.parsed_body['account_id']
      expect(new_id).not_to eq(erased_id)
      expect(Account.exists?(erased_id)).to be(false)
      fresh = Account.find(new_id)
      expect(fresh.conversations.count).to eq(0)
      expect(fresh.contacts.count).to eq(0)
      expect(provisioned).to have_attributes(state: 'active', account_id: new_id, erased_at: nil, erase_after: nil)
      expect(provisioned.storefront_inbox.account_id).to eq(new_id)
      expect(Inclamo::ProvisionedAccount.count).to eq(1)
    end

    it 'answers a later erasure request by the new account\'s state' do
      provision
      ask_erasure
      expect(response.parsed_body).to eq('error' => 'account_active')

      remove_app
      ask_erasure
      expect(response.parsed_body).to include('state' => 'scheduled')
      expect(store_record.account_id).to eq(provisioned.account_id)
    end

    it 'answers the status call and the removal as for a store without an account' do
      ask_status
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')

      remove_app
      expect(response.parsed_body).to eq('contract' => 1, 'state' => 'none')
      expect(provisioned.state).to eq('erased')
    end
  end
end
