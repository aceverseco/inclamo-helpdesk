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
