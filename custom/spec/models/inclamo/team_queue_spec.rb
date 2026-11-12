# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::TeamQueue do
  let(:account) { create(:account) }
  let(:queues) { described_class.where(account_id: account.id).ordered }

  it 'ships a name and a query for each of the eight ready queues' do
    expect(Inclamo::TeamQueues::READY.keys).to eq(%w[urgent ai_handover overdue delivery cancellation damage missing_parts return])
    Inclamo::TeamQueues::READY.each_key do |key|
      expect(Inclamo::TeamQueues.shipped_name(key)).to be_present
      expect(Inclamo::TeamQueues.shipped_query(key)['payload'].last).not_to have_key('query_operator')
    end
  end

  it 'keeps one queue per key in an account' do
    duplicate = described_class.new(account: account, key: 'urgent', name: 'Again', query: {})

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'places a ready queue at its shipped place and leaves no two queues at one position' do
    own = described_class.create!(account: account, name: 'Own', position: 3, query: {})
    moved = queues.find_by(key: 'missing_parts')
    moved.update!(position: 1)

    Inclamo::TeamQueues.place!(moved)

    listed = described_class.where(account_id: account.id).ordered
    expect(listed.pluck(:position)).to eq((1..9).to_a)
    expect(listed.pluck(:key).compact).to eq(Inclamo::TeamQueues::READY.keys)
    expect(listed.pluck(:id).index(own.id)).to be < listed.pluck(:id).index(moved.id)
  end

  it 'counts nothing, and does not raise, for a queue without usable conditions' do
    admin = create(:user, account: account, role: :administrator)
    empty = described_class.create!(account: account, name: 'Empty', position: 20, query: {})
    broken = described_class.create!(account: account, name: 'Broken', position: 21,
                                     query: { 'payload' => [Inclamo::TeamQueues.condition('no_such_attribute', ['x'])] })

    expect(Inclamo::TeamQueues.count(empty, admin)).to be_nil
    expect(Inclamo::TeamQueues.count(broken, admin)).to be_nil
    expect(Inclamo::TeamQueues.count(queues.find_by(key: 'urgent'), admin)).to eq(0)
  end

  it 'refuses a queue without a name' do
    expect(queues.first.update(name: ' ')).to be(false)
  end

  it 'shows at most twenty queues' do
    12.times { |index| described_class.create!(account: account, name: "Own #{index}", position: 20 + index, query: {}) }
    extra = described_class.new(account: account, name: 'One too many', query: {})

    expect(queues.visible.count).to eq(20)
    expect(extra).not_to be_valid
    expect(extra.errors.of_kind?(:hidden, :too_many_visible)).to be(true)
    extra.hidden = true
    expect(extra).to be_valid
  end
end
