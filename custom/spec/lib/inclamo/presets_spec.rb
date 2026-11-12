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
