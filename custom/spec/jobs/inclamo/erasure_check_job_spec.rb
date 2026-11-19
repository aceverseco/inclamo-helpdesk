# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/erasure_requests')

# The daily erasure run: which stores it takes, under the store's lock, and the
# record it keeps tidy.
RSpec.describe Inclamo::ErasureCheckJob, type: :request do
  include_context 'with app provisioning'
  include ErasureRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }

  around { |example| travel_to(now) { example.run } }

  before do
    suspended_store
    account
    ask_erasure
  end

  it 'runs on the schedule queue' do
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
    expect(Inclamo::StoreErasureJob.new.queue_name).to eq('scheduled_jobs')
  end

  it 'takes a suspended store whose time has passed, and hands its account to the erasure' do
    travel 7.days + 1.second

    expect { described_class.perform_now }.to have_enqueued_job(Inclamo::StoreErasureJob).with(store_record.id)

    expect(provisioned).to have_attributes(state: 'erasing', account_id: nil, erase_after: nil, storefront_inbox_id: nil)
    expect(store_record).to have_attributes(state: 'erasing', account_id: account.id)
    expect(Account.exists?(account.id)).to be(true)
  end

  it 'leaves a store whose time has not come yet' do
    travel 7.days - 1.minute

    expect { described_class.perform_now }.not_to have_enqueued_job(Inclamo::StoreErasureJob)

    expect(provisioned).to have_attributes(state: 'suspended', account_id: account.id, erase_after: now + 7.days)
    expect(store_record.state).to eq('scheduled')
  end

  it 'does not take a store whose account was restored between the selection and the lock' do
    travel 8.days
    selected = Inclamo::ProvisionedAccount.where(state: 'suspended').where(erase_after: ..Time.current).to_a
    expect(selected).to eq([provisioned])

    provision
    expect(response.parsed_body['outcome']).to eq('restored')

    expect(Inclamo::Erasure::Store.begin!(selected.first)).to be_nil
    expect(provisioned).to have_attributes(state: 'active', account_id: account.id)
    expect(account.reload).to be_active
    expect(store_record.state).to eq('cancelled')
  end

  it 'withdraws the erasure of an account the operator made active again, and erases nothing' do
    account.update!(status: :active)
    travel 8.days

    expect { described_class.perform_now }.not_to have_enqueued_job(Inclamo::StoreErasureJob)

    expect(provisioned).to have_attributes(state: 'suspended', account_id: account.id, erase_after: nil)
    expect(store_record.state).to eq('cancelled')
    expect(events_of.last).to eq('erasure_cancelled')
  end

  it 'takes each store once, even when two runs meet' do
    travel 8.days
    row = provisioned

    first = Inclamo::Erasure::Store.begin!(row)
    second = Inclamo::Erasure::Store.begin!(Inclamo::ProvisionedAccount.find(row.id))

    expect(first).to be_present
    expect(second).to be_nil
    expect(Inclamo::ErasureRequest.stores.where(state: 'erasing').count).to eq(1)
  end

  it 'starts again, with an alert, an erasure under way for more than a day' do
    travel 8.days
    described_class.perform_now
    record = store_record
    allow(Rails.logger).to receive(:error)

    travel 1.day + 1.minute
    expect { described_class.perform_now }.to have_enqueued_job(Inclamo::StoreErasureJob).with(record.id)

    expect(Rails.logger).to have_received(:error).with(/ALERT the erasure of #{ProvisioningRequests::STORE} \(record #{record.id}\)/)
  end

  describe 'the record' do
    def record_of(kind, state, completed_at: nil, **attributes)
      Inclamo::ErasureRequest.create!(kind: kind, shop_domain: 'other-store.myshopify.com', state: state, received_at: 200.days.ago,
                                      completed_at: completed_at, **attributes)
    end

    it 'removes requests completed more than 90 days ago, and keeps held, waiting and recent ones of any age' do
      old_store = record_of('store', 'erased', completed_at: 91.days.ago)
      old_cancel = record_of('store', 'cancelled', completed_at: 91.days.ago)
      old_done = record_of('shopper_erasure', 'done', completed_at: 91.days.ago, done_by: 'automatic')
      recent = record_of('store', 'erased', completed_at: 89.days.ago)
      held = record_of('shopper_erasure', 'held', held_at: 150.days.ago, hold_reason: 'open payment dispute')
      waiting = record_of('shopper_data_request', 'waiting')

      described_class.perform_now

      expect(Inclamo::ErasureRequest.where(id: [old_store, old_cancel, old_done].map(&:id))).to be_empty
      expect(Inclamo::ErasureRequest.where(id: [recent, held, waiting].map(&:id)).count).to eq(3)
      expect(store_record.state).to eq('scheduled')
    end
  end
end
