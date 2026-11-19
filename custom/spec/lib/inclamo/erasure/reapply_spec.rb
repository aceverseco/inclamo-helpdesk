# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/erasure_requests')

# The journal of completed erasures, kept outside the database, and applying
# it again after the database was restored from a backup taken before an
# erasure (docs/app-store-erasure.md §7).
RSpec.describe Inclamo::Erasure::Reapply, type: :request do
  include_context 'with app provisioning'
  include ErasureRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:dir) { Dir.mktmpdir('inclamo-erasure-journal') }
  let(:journal) { File.join(dir, 'erasures.jsonl') }
  let(:account) { provisioned.account }

  around do |example|
    travel_to(now) do
      with_modified_env(INCLAMO_ERASURE_JOURNAL_PATH: journal) { example.run }
    end
  ensure
    FileUtils.remove_entry(dir)
  end

  def lines
    File.readlines(journal).map { |line| JSON.parse(line) }
  end

  describe 'the journal' do
    it 'gets one line for each completed erasure, naming the store, the account and the times, and no person' do
      suspended_store
      account_id = account.id
      ask_erasure
      travel 7.days + 1.minute

      run_erasures

      expect(lines).to eq([{ 'kind' => 'store', 'shop_domain' => ProvisioningRequests::STORE, 'account_id' => account_id,
                             'received_at' => '2026-11-20T10:00:00Z', 'completed_at' => '2026-11-27T10:01:00Z' }])
      expect(File.read(journal)).not_to include('alex@example.test')
      expect(File.stat(journal).mode & 0o777).to eq(0o600)
    end

    it 'is not written where the operator set no place, and the erasure completes with a warning' do
      suspended_store
      ask_erasure
      travel 8.days
      allow(Rails.logger).to receive(:warn)

      with_modified_env(INCLAMO_ERASURE_JOURNAL_PATH: nil) { run_erasures }

      expect(File.exist?(journal)).to be(false)
      expect(provisioned.state).to eq('erased')
      expect(Rails.logger).to have_received(:warn).with(/no journal configured/)
    end

    it 'keeps the erasure under way while its place cannot be written' do
      suspended_store
      ask_erasure
      travel 8.days
      allow(Rails.logger).to receive(:error)

      with_modified_env(INCLAMO_ERASURE_JOURNAL_PATH: File.join(dir, 'missing', 'erasures.jsonl')) { run_erasures }

      expect(provisioned.state).to eq('erasing')
      expect(store_record.state).to eq('erasing')
      expect(Rails.logger).to have_received(:error).with(/ALERT the erasure journal cannot be written/)
    end
  end

  describe 'after a restore' do
    # The database as a backup taken before the erasure holds it: the store's
    # account with its conversations, and the erasure scheduled. The journal,
    # outside the database, holds the line the completed erasure wrote.
    before do
      suspended_store
      create_list(:conversation, 2, account: account, inbox: create(:inbox, account: account))
      ask_erasure
      record = store_record
      Inclamo::Erasure::Journal.append(
        Inclamo::Erasure::Journal.store_entry(record.dup.tap { |line| line.assign_attributes(completed_at: now + 7.days + 1.minute) })
      )
      travel 9.days
    end

    it 'erases the store again, finishes the restored record, and reports it' do
      account_id = account.id

      started = perform_enqueued_jobs { described_class.new(journal).call }

      expect(started.map { |one| one.line['account_id'] }).to eq([account_id])
      expect(started.first.record.state).to eq('erased')
      expect(Account.exists?(account_id)).to be(false)
      expect(Conversation.where(account_id: account_id)).to be_empty
      expect(Inclamo::Erasure::Leftovers.account(account_id)).to eq([])
      expect(provisioned).to have_attributes(state: 'erased', account_id: nil)
      expect(Inclamo::ErasureRequest.stores.pluck(:state)).to eq(['erased'])
    end

    it 'erases nothing more on a second run' do
      perform_enqueued_jobs { described_class.new(journal).call }

      expect { expect(described_class.new(journal).call).to eq([]) }.not_to change(Account, :count)
    end

    it 'erases the account even when the backup was taken before the store was removed' do
      provision
      expect(provisioned.state).to eq('active')

      perform_enqueued_jobs { described_class.new(journal).call }

      expect(Account.exists?(store_record.account_id)).to be(false)
      expect(provisioned.state).to eq('erased')
    end

    it 'never takes an account created after the erasure, whatever its id' do
      line = lines.first
      later = create(:account, created_at: now + 8.days)
      File.write(journal, "#{line.merge('account_id' => later.id).to_json}\nnot json\n", mode: 'a')

      perform_enqueued_jobs { described_class.new(journal).call }

      expect(Account.exists?(later.id)).to be(true)
    end

    it 'runs as the task the operator is told to run, and says what it erased' do
      task = Rake::Task['inclamo:erasure:reapply']
      task.reenable

      expect { perform_enqueued_jobs { task.invoke(journal) } }
        .to output(/Store #{ProvisioningRequests::STORE}, account \d+ \(erased 2026-11-27T10:01:00Z\): erased again/).to_stdout
      task.reenable
      expect { task.invoke(journal) }.to output("Nothing to erase again.\n").to_stdout
    end
  end
end
