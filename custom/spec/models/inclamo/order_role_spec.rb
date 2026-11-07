# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::OrderRole do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def member(user, in_account = account)
    AccountUser.find_by(account: in_account, user: user)
  end

  it 'always allows an administrator' do
    expect(described_class.allows?(member(admin))).to be(true)
  end

  it 'does not allow an agent without the role, a new agent included' do
    expect(described_class.allows?(member(agent))).to be(false)
  end

  it 'allows an agent holding the role' do
    described_class.create!(account_user: member(agent), granted_by: admin)

    expect(described_class.allows?(member(agent))).to be(true)
  end

  it 'does not carry over to another account of the same user' do
    other = create(:account)
    create(:account_user, account: other, user: agent, role: :agent)
    described_class.create!(account_user: member(agent), granted_by: admin)

    expect(described_class.allows?(member(agent, other))).to be(false)
  end

  it 'allows nobody without a membership' do
    expect(described_class.allows?(nil)).to be(false)
  end

  it 'is lost when the agent is removed from the account, so adding them again starts without it' do
    described_class.create!(account_user: member(agent), granted_by: admin)

    member(agent).destroy!

    expect(described_class.count).to eq(0)
  end
end
