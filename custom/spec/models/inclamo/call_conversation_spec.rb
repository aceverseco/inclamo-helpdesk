# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::CallConversation do
  let(:account) { create(:account) }

  def key(of_account, call_id)
    described_class.create!(account: of_account, call_id: call_id, created_at: Time.current)
  end

  it 'holds one row per call id in an account' do
    key(account, 'c-1')

    expect { key(account, 'c-1') }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { key(account, 'c-2') }.to change(described_class, :count).by(1)
  end

  it 'lets two accounts have a call with the same id' do
    key(account, 'c-1')

    expect { key(create(:account), 'c-1') }.to change(described_class, :count).by(1)
  end

  it 'goes with its conversation' do
    conversation = create(:conversation, account: account)
    key(account, 'c-1').update!(conversation: conversation, contact_id: conversation.contact_id, matched_by: 'phone')

    expect { conversation.destroy! }.to change(described_class, :count).by(-1)
  end
end
