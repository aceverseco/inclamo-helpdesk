# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::Ai::Calls::Attributes do
  include AiServiceStubs

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:website) { create(:inbox, account: account, name: 'Website') }
  let(:keys) { described_class::DEFINITIONS.keys }

  before do
    resolve_ai_service_publicly
    stub_ai_registration
    stub_ai_removal
  end

  def connect
    Inclamo::Ai::Connect.call(account: account, user: admin, code: ai_code, inbox_ids: [website.id])
  end

  def defined
    account.custom_attribute_definitions.conversation_attribute.where(attribute_key: keys)
  end

  it 'defines the eight attributes of a call when the AI agent is connected' do
    connect

    expect(defined.pluck(:attribute_key)).to match_array(keys)
    expect(keys.size).to eq(8)
    expect(defined.find_by(attribute_key: 'inclamo_call_duration').attribute_display_type).to eq('number')
    expect(defined.find_by(attribute_key: 'inclamo_call_recording').attribute_display_type).to eq('link')
    expect(defined.find_by(attribute_key: 'inclamo_call_ended_at').attribute_display_type).to eq('date')
  end

  it 'keeps them through a disconnection and adds none at the next connection' do
    connect
    Inclamo::Ai::Disconnect.call(account: account)
    expect(defined.count).to eq(8)

    expect { connect }.not_to(change { defined.pluck(:id, :updated_at) })
  end

  it 'keeps a definition the merchant already has under the same key' do
    own = account.custom_attribute_definitions.create!(
      attribute_key: 'inclamo_call_outcome', attribute_model: :conversation_attribute,
      attribute_display_name: 'Result of the call', attribute_display_type: :text
    )

    connect

    expect(own.reload.attribute_display_name).to eq('Result of the call')
    expect(defined.count).to eq(8)
  end
end
