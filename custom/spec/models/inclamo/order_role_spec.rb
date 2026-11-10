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

  it 'permits only the selected action and keeps discount grants separate' do
    grant = described_class.create!(account_user: member(agent), permissions: ['address'])
    expect(Inclamo::ActionPermissions.for(member(agent)).select { |_, allowed| allowed }.keys).to eq(['address'])
    expect(described_class.allows?(member(agent), 'refund')).to be(false)
    Inclamo::DiscountGrant.create!(account_user: member(agent))
    expect(Inclamo::ActionPermissions.allows?(member(agent), 'discount')).to be(true)
    expect(grant.reload.permissions).to eq(['address'])
  end

  it 'rechecks a previously loaded administrator after demotion or membership removal' do
    loaded = member(admin)
    AccountUser.where(id: loaded.id).update_all(role: AccountUser.roles[:agent])
    expect(Inclamo::ActionPermissions.allows?(loaded, 'refund')).to be(false)
    loaded.destroy!
    expect(Inclamo::ActionPermissions.allows?(loaded, 'refund')).to be(false)
  end

  it 'does not accept unknown or duplicate permission names' do
    expect(described_class.new(account_user: member(agent), permissions: ['delete_store'])).not_to be_valid
    expect(described_class.new(account_user: member(agent), permissions: %w[address address])).not_to be_valid
  end

  it 'adds and removes individual rights without changing other grants' do
    membership = member(agent)
    Inclamo::ActionPermissions.set!(membership, 'address', true, by: admin)
    Inclamo::ActionPermissions.set!(membership, 'refund', true, by: admin)
    Inclamo::ActionPermissions.set!(membership, 'address', false, by: admin)
    expect(described_class.find_by(account_user: membership).permissions).to eq(['refund'])
  end

  it 'is lost when the agent is removed from the account, so adding them again starts without it' do
    described_class.create!(account_user: member(agent), granted_by: admin)

    member(agent).destroy!

    expect(described_class.count).to eq(0)
  end
end
