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

  describe 'the door a connection came through' do
    it 'reads as made on the page unless it says otherwise, as every connection made before the column' do
      expect(create(:inclamo_ai_connection).reload.connected_via).to eq('page')
      expect(described_class.columns_hash['connected_via']).to have_attributes(default: 'page', null: false)
    end

    it 'knows the page and the store app, and nothing else' do
      expect(build(:inclamo_ai_connection, connected_via: 'app')).to be_valid
      expect(build(:inclamo_ai_connection, connected_via: 'elsewhere')).not_to be_valid
      record = create(:inclamo_ai_connection)
      expect { record.update_column(:connected_via, 'elsewhere') }.to raise_error(ActiveRecord::StatementInvalid) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'needs no person for a connection the app made' do
      expect(create(:inclamo_ai_connection, connected_via: 'app', connected_by: nil)).to be_persisted
    end
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
