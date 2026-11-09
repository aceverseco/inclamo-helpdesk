# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::AiConnection do
  it 'allows one connection per account' do
    first = create(:inclamo_ai_connection)
    second = build(:inclamo_ai_connection, account: first.account)

    expect(second).not_to be_valid
    expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'knows the three states, and that a disconnected one is not active' do
    expect(described_class.states.keys).to eq(%w[connected failing disconnected])
    expect(build(:inclamo_ai_connection, state: 'failing')).to be_active
    expect(build(:inclamo_ai_connection, state: 'disconnected')).not_to be_active
  end

  it 'is refused on an installation without encryption keys, but can still be marked disconnected' do
    record = create(:inclamo_ai_connection)
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

    expect(build(:inclamo_ai_connection)).not_to be_valid
    expect(build(:inclamo_ai_connection).tap(&:valid?).errors[:base].join).to include('encryption')
    expect(record.update(state: 'disconnected')).to be(true)
  end

  it 'covers only its connected inboxes, and none once disconnected' do
    record = build(:inclamo_ai_connection, inbox_ids: [3, 5])

    expect(record.covers?(3)).to be(true)
    expect(record.covers?('5')).to be(true)
    expect(record.covers?(4)).to be(false)
    record.state = 'disconnected'
    expect(record.covers?(3)).to be(false)
  end

  describe 'delivery health' do
    let(:record) { create(:inclamo_ai_connection) }

    it 'turns failing on a failure and connected on the next delivery' do
      described_class.record_failure(record.id, 'http_503')
      expect(record.reload).to have_attributes(state: 'failing', last_error: 'http_503', last_failed_at: be_present)

      described_class.record_delivery(record.id)
      expect(record.reload).to have_attributes(state: 'connected', last_delivered_at: be_present, last_error: 'http_503')
    end

    it 'never brings a disconnected connection back' do
      record.update!(state: 'disconnected')

      described_class.record_delivery(record.id)
      described_class.record_failure(record.id, 'timeout')

      expect(record.reload).to have_attributes(state: 'disconnected', last_delivered_at: nil, last_failed_at: nil)
    end
  end
end
