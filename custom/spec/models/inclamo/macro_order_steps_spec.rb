# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Macro, 'with order steps' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def steps(*names)
    names.map { |name| { 'action_name' => name, 'action_params' => name == 'send_message' ? ['Sorry, we refunded you.'] : [] } }
  end

  it 'saves a macro with an order step among Chatwoot steps, in their order' do
    macro = described_class.create!(account: account, name: 'Refund and close', created_by: admin, visibility: :global,
                                    actions: steps('inclamo_refund_full', 'send_message', 'resolve_conversation'))

    expect(macro.reload.actions.pluck('action_name')).to eq(%w[inclamo_refund_full send_message resolve_conversation])
  end

  it 'accepts each of the four order steps' do
    macro = build(:macro, account: account, actions: steps('inclamo_refund_full', 'inclamo_refund_shipping', 'inclamo_cancel_order', 'inclamo_replacement'))

    expect(macro).to be_valid
  end

  it 'still refuses a step nobody knows' do
    macro = build(:macro, account: account, actions: steps('inclamo_refund_full', 'inclamo_delete_store'))

    expect(macro).not_to be_valid
    expect(macro.errors[:actions].join).to include('inclamo_delete_store')
    expect(macro.errors[:actions].join).not_to include('inclamo_refund_full')
  end

  it 'leaves automation rules without order steps' do
    rule = build(:automation_rule, account: account, actions: steps('inclamo_refund_full'))

    expect(rule).not_to be_valid
    expect(rule.errors[:actions].join).to include('inclamo_refund_full')
  end
end
