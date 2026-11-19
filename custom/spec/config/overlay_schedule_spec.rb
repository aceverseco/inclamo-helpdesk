# frozen_string_literal: true

require 'rails_helper'

# The overlay adds its periodic jobs to Chatwoot's schedule from
# custom/config/overlay.rb, in a block that runs only inside Sidekiq's own
# process. This runs that block as Sidekiq's process would and reads what it
# asks sidekiq-cron for.
RSpec.describe 'The overlay schedule' do # rubocop:disable RSpec/DescribeClass
  # Chatwoot loads its own schedule in the same way; none of it is written to
  # Redis here.
  before do
    allow(Sidekiq::Cron).to receive(:configure)
    allow(Sidekiq::Cron::Job).to receive_messages(load_from_hash!: nil, load_from_hash: nil, destroy: nil)
  end

  let(:entries) do
    asked = []
    allow(Sidekiq).to receive(:server?).and_return(true)
    allow(Sidekiq::Cron::Job).to receive(:create) { |entry| asked << entry }
    Rails.application.reloader.prepare!
    asked
  end

  let(:cleanup) { entries.find { |entry| entry[:name] == 'inclamo_provisioning_events_cleanup_job' } }

  it 'holds the removal of old provisioning records, once a day' do
    expect(cleanup).to eq(name: 'inclamo_provisioning_events_cleanup_job', cron: '40 3 * * *',
                          class: 'Inclamo::ProvisioningEventsCleanupJob', queue: 'scheduled_jobs')
    expect(entries.count { |entry| entry[:class] == 'Inclamo::ProvisioningEventsCleanupJob' }).to eq(1)
  end

  it 'names a job that exists and runs on the queue of the schedule' do
    job = cleanup[:class].constantize

    expect(job).to be < ApplicationJob
    expect(job.new.queue_name).to eq(cleanup[:queue])
  end

  it 'gives sidekiq-cron an entry it accepts, due once in a day' do
    entry = Sidekiq::Cron::Job.new(cleanup)
    day = Time.utc(2026, 1, 1)..Time.utc(2026, 1, 2)

    expect(entry).to be_valid
    expect(Fugit.parse_cron(cleanup[:cron]).within(day).map { |time| time.to_t.utc.strftime('%H:%M') }).to eq(['03:40'])
  end

  it 'holds the daily erasure run, once a day, and every few seconds only in the end-to-end stack' do
    erasure = entries.find { |entry| entry[:name] == 'inclamo_erasure_check_job' }
    day = Time.utc(2026, 1, 1)..Time.utc(2026, 1, 2)

    expect(erasure).to eq(name: 'inclamo_erasure_check_job', cron: '10 4 * * *', class: 'Inclamo::ErasureCheckJob', queue: 'scheduled_jobs')
    expect(Sidekiq::Cron::Job.new(erasure)).to be_valid
    expect(Fugit.parse_cron(erasure[:cron]).within(day).count).to eq(1)
    expect(erasure[:class].constantize.new.queue_name).to eq(erasure[:queue])
    with_modified_env(INCLAMO_ERASURE_CHECK_SECONDS: '5', INCLAMO_E2E: nil) { expect(Inclamo::Erasure.check_cron).to eq('10 4 * * *') }
    with_modified_env(INCLAMO_ERASURE_CHECK_SECONDS: '5', INCLAMO_E2E: '1') { expect(Inclamo::Erasure.check_cron).to eq('*/5 * * * * *') }
  end

  it 'asks for nothing outside Sidekiq\'s own process' do
    asked = []
    allow(Sidekiq).to receive(:server?).and_return(false)
    allow(Sidekiq::Cron::Job).to receive(:create) { |entry| asked << entry }
    Rails.application.reloader.prepare!

    expect(asked).to be_empty
  end
end
