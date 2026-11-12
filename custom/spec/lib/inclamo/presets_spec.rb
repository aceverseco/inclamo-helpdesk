# frozen_string_literal: true

require 'rails_helper'

# The repeatable installation of the ready queues and saved replies.
RSpec.describe Inclamo::Presets do
  let(:account) { create(:account) }
  let(:queues) { Inclamo::TeamQueue.where(account_id: account.id).ordered }
  let(:replies) { account.canned_responses }

  describe 'team queues' do
    it 'a new account has the eight ready queues, in the shipped order, and their labels' do
      expect(queues.pluck(:name)).to eq(['Urgent', 'Handed over by AI', 'Overdue', 'Delivery', 'Cancellation', 'Damage', 'Missing parts', 'Return'])
      expect(queues.pluck(:position)).to eq((1..8).to_a)
      expect(queues).to all(have_attributes(hidden: false))
      expect(account.labels.pluck(:title)).to match_array(%w[sla-overdue delivery cancellation damage missing-parts return])
    end

    it 'an account without them gets them, as on upgrade' do
      queues.delete_all

      described_class.install(account)

      expect(queues.count).to eq(8)
    end

    it 'a second run creates nothing and keeps a renamed, a moved and a hidden queue as they are' do
      queues.find_by(key: 'missing_parts').update!(name: 'Parts requests', position: 1)
      queues.find_by(key: 'cancellation').update!(hidden: true)
      labels = account.labels.count

      2.times { described_class.install(account) }

      expect(queues.count).to eq(8)
      expect(queues.find_by(key: 'missing_parts')).to have_attributes(name: 'Parts requests', position: 1)
      expect(queues.find_by(key: 'cancellation')).to have_attributes(hidden: true)
      expect(account.labels.count).to eq(labels)
    end

    it "uses a store's own label of the same title as it is" do
      label = account.labels.find_by(title: 'return')
      label.update!(color: '#000000', description: 'Ours')

      described_class.install(account)

      expect(account.labels.where(title: 'return').sole).to have_attributes(color: '#000000', description: 'Ours')
    end

    it 'does not fail the caller when an installer fails' do
      allow(Inclamo::TeamQueues::Installer).to receive(:call).and_raise(StandardError, 'no')

      expect { described_class.install(account) }.not_to raise_error
    end
  end

  describe 'the migration for accounts older than the ready presets' do
    require Rails.root.join('custom/db/migrate/20261112100200_install_inclamo_ready_presets')

    let(:migration) { InstallInclamoReadyPresets.new.tap { |one| one.verbose = false } }

    it 'gives an account without queues and replies all of them' do
      queues.delete_all
      Inclamo::PresetInstall.where(account_id: account.id).delete_all
      CannedResponse.where(account_id: account.id).delete_all

      migration.up

      expect(queues.pluck(:key)).to eq(Inclamo::TeamQueues::READY.keys)
      expect(replies.count).to eq(5)
    end

    it 'fails, naming the account it could not serve, and still serves the others' do
      other = create(:account)
      [account, other].each { |one| Inclamo::TeamQueue.where(account_id: one.id).delete_all }
      allow(Inclamo::TeamQueues::Installer).to receive(:call).and_call_original
      allow(Inclamo::TeamQueues::Installer).to receive(:call).with(account).and_raise(StandardError, 'no')

      expect { migration.up }.to raise_error(RuntimeError, /not installed for accounts #{account.id}\b/)

      expect(queues.count).to eq(0)
      expect(Inclamo::TeamQueue.where(account_id: other.id).count).to eq(8)
    end
  end

  describe 'install!' do
    it 'raises what failed, after the other installer has run' do
      replies_before = replies.count
      CannedResponse.where(account_id: account.id).delete_all
      Inclamo::PresetInstall.where(account_id: account.id).delete_all
      allow(Inclamo::TeamQueues::Installer).to receive(:call).and_raise(StandardError, 'no')

      expect { described_class.install!(account) }.to raise_error(StandardError, 'no')
      expect(replies.count).to eq(replies_before)
    end
  end

  describe 'the repair' do
    it 'finds an account that lacks a queue or a reply never offered, and no complete one' do
      complete = create(:account)
      no_queue = create(:account)
      no_reply = create(:account)
      Inclamo::TeamQueue.where(account_id: no_queue.id, key: 'damage').delete_all
      Inclamo::PresetInstall.where(account_id: no_reply.id, key: 'return').delete_all
      # A reply the store deleted was offered: that account is complete.
      complete.canned_responses.find_by(short_code: 'return-start').destroy!

      expect(described_class.incomplete.where(id: [account.id, complete.id, no_queue.id, no_reply.id]).pluck(:id)).to match_array([no_queue.id, no_reply.id])
    end

    it 'installs what is missing, at its shipped place, and leaves the rest as it is' do
      queues.find_by(key: 'urgent').update!(name: 'Fire')
      queues.find_by(key: 'damage').destroy!

      expect(Inclamo::PresetsRepairJob.perform_now).to eq([])

      expect(queues.pluck(:key)).to eq(Inclamo::TeamQueues::READY.keys)
      expect(queues.pluck(:position)).to eq((1..8).to_a)
      expect(queues.find_by(key: 'urgent').name).to eq('Fire')
      expect(described_class.incomplete.where(id: account.id)).to be_empty
    end

    it 'goes on to the next account when one fails, and answers the ones it could not serve' do
      other = create(:account)
      [account, other].each { |one| Inclamo::TeamQueue.where(account_id: one.id, key: 'damage').delete_all }
      allow(Inclamo::TeamQueues::Installer).to receive(:call).and_call_original
      allow(Inclamo::TeamQueues::Installer).to receive(:call).with(account).and_raise(StandardError, 'no')

      failed = nil
      expect { failed = described_class.repair }.not_to raise_error

      expect(failed).to include(account.id)
      expect(failed).not_to include(other.id)
      expect(Inclamo::TeamQueue.where(account_id: other.id).count).to eq(8)
    end

    it 'serves a bounded number of accounts a run, oldest first' do
      older = account
      newer = create(:account)
      [older, newer].each { |one| Inclamo::TeamQueue.where(account_id: one.id, key: 'damage').delete_all }
      allow(described_class).to receive(:incomplete).and_return(Account.where(id: [account.id, newer.id]))

      described_class.repair(limit: 1)

      expect(queues.count).to eq(8)
      expect(Inclamo::TeamQueue.where(account_id: newer.id).count).to eq(7)
    end
  end

  describe 'ready replies' do
    it 'a new account has the five replies, with the order variables of their categories' do
      expect(replies.pluck(:short_code)).to match_array(%w[delivery-status cancel-confirm damage-photos missing-part return-start])
      expect(replies.find_by(short_code: 'delivery-status').content).to include('{{order.number}}', '{{order.tracking_link}}')
      expect(replies.find_by(short_code: 'cancel-confirm').content).to include('{{order.number}}')
      expect(replies.find_by(short_code: 'return-start').content).to include('{{order.number}}')
    end

    it 'keeps an edited reply and creates no second one' do
      replies.find_by(short_code: 'return-start').update!(content: 'Our own words')

      described_class.install(account)

      expect(replies.where(short_code: 'return-start').sole.content).to eq('Our own words')
      expect(replies.count).to eq(5)
    end

    it 'does not bring back a deleted reply' do
      replies.find_by(short_code: 'damage-photos').destroy!

      described_class.install(account)

      expect(replies.exists?(short_code: 'damage-photos')).to be(false)
    end

    it "leaves the store's own reply under a taken short code and records the offer" do
      Inclamo::PresetInstall.where(account_id: account.id).delete_all
      CannedResponse.where(account_id: account.id).delete_all
      replies.create!(short_code: 'cancel-confirm', content: 'The store wrote this')

      2.times { described_class.install(account) }

      expect(replies.where(short_code: 'cancel-confirm').sole.content).to eq('The store wrote this')
      expect(replies.count).to eq(5)
      expect(Inclamo::PresetInstall.find_by(account_id: account.id, kind: 'ready_reply', key: 'cancellation')).to have_attributes(created: false)
    end
  end
end
