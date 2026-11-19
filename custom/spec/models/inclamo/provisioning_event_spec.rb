# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::ProvisioningEvent do
  let(:request_id) { SecureRandom.uuid }

  it 'holds the time, the domain, the outcome, the request id and the account, and has no other column' do
    event = described_class.record(outcome: 'created', shop_domain: 'Example-Store.myshopify.com', request_id: request_id.upcase)

    expect(event.reload.attributes.keys).to contain_exactly('id', 'shop_domain', 'outcome', 'request_id', 'account_id', 'created_at')
    expect(event).to have_attributes(shop_domain: 'example-store.myshopify.com', outcome: 'created', request_id: request_id)
    expect(event.created_at).to be_within(5.seconds).of(Time.current)
  end

  it 'keeps a domain or a request id only when it reads as one' do
    event = described_class.record(outcome: 'refused', shop_domain: 'alex@example.test <script>', request_id: 'Alex Example')

    expect(event.reload).to have_attributes(shop_domain: nil, request_id: nil, outcome: 'refused')
  end

  it 'never fails the request it describes' do
    expect(described_class.record(outcome: 'unheard-of', shop_domain: 'a.myshopify.com', request_id: request_id)).to be_nil
  end

  it 'has the daily job remove records older than 90 days and no others' do
    old = described_class.create!(outcome: 'created', shop_domain: 'old.myshopify.com', created_at: 91.days.ago)
    edge = described_class.create!(outcome: 'created', shop_domain: 'edge.myshopify.com', created_at: 89.days.ago)
    fresh = described_class.record(outcome: 'existed', shop_domain: 'fresh.myshopify.com', request_id: request_id)

    Inclamo::ProvisioningEventsCleanupJob.perform_now

    expect(described_class.where(id: [old.id, edge.id, fresh.id]).pluck(:id)).to contain_exactly(edge.id, fresh.id)
    expect(Inclamo::ProvisioningEventsCleanupJob.new.queue_name).to eq('scheduled_jobs')
  end
end
