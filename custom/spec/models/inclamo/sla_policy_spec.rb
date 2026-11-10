# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::SlaPolicy do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def policy(**attributes)
    described_class.create!({ account: account, name: 'Standard', first_response_seconds: 7200 }.merge(attributes))
  end

  it 'needs at least one of the two targets' do
    empty = described_class.new(account: account, name: 'Empty')

    expect(empty).not_to be_valid
    expect(empty.errors.map(&:message)).to include(I18n.t('inclamo.sla.errors.target_needed'))
    expect(described_class.new(account: account, name: 'Resolution only', resolution_seconds: 3600)).to be_valid
    expect(described_class.new(account: account, name: 'First response only', first_response_seconds: 600)).to be_valid
  end

  it 'refuses a target of zero, a negative one and one above a year' do
    expect(described_class.new(account: account, name: 'Zero', first_response_seconds: 0)).not_to be_valid
    expect(described_class.new(account: account, name: 'Negative', resolution_seconds: -60)).not_to be_valid
    expect(described_class.new(account: account, name: 'Long', resolution_seconds: 366 * 86_400)).not_to be_valid
  end

  it 'needs a name' do
    expect(described_class.new(account: account, first_response_seconds: 60)).not_to be_valid
  end

  it 'covers chosen inboxes of its own account only' do
    other = create(:inbox, account: create(:account))

    expect(described_class.new(account: account, name: 'None chosen', first_response_seconds: 60, all_inboxes: false)).not_to be_valid
    expect(described_class.new(account: account, name: 'Foreign', first_response_seconds: 60, all_inboxes: false, inbox_ids: [other.id])).not_to be_valid

    chosen = policy(all_inboxes: false, inbox_ids: [inbox.id.to_s, inbox.id])
    expect(chosen.inbox_ids).to eq([inbox.id])
    expect(chosen.covers?(inbox.id)).to be(true)
    expect(chosen.covers?(create(:inbox, account: account).id)).to be(false)
  end

  it 'drops a chosen inbox deleted since, so the policy can still be saved' do
    kept = create(:inbox, account: account)
    record = policy(all_inboxes: false, inbox_ids: [inbox.id, kept.id])
    inbox.destroy!

    record.update!(name: 'Renamed', inbox_ids: [inbox.id, kept.id])

    expect(record.reload).to have_attributes(name: 'Renamed', inbox_ids: [kept.id])
    expect(record.update(inbox_ids: [kept.id, create(:inbox, account: create(:account)).id])).to be(false)
  end

  it 'says which target is out of range, and that its limit is 365 days' do
    record = described_class.new(account: account, name: 'Long', first_response_seconds: 400 * 86_400, resolution_seconds: 0)

    expect(record).not_to be_valid
    expect(record.errors.map(&:message)).to contain_exactly(I18n.t('inclamo.sla.errors.first_response_range'),
                                                            I18n.t('inclamo.sla.errors.resolution_range'))
    expect(I18n.t('inclamo.sla.errors.first_response_range')).to include('first-response', '365 days')
  end

  it 'needs both switches set, with a message for each' do
    record = described_class.new(account: account, name: 'Unset', first_response_seconds: 60, business_hours_only: nil, all_inboxes: nil)

    expect(record).not_to be_valid
    expect(record.errors.map(&:message)).to include(I18n.t('inclamo.sla.errors.business_hours_needed'),
                                                    I18n.t('inclamo.sla.errors.all_inboxes_needed'))
  end

  it 'forgets chosen inboxes once it covers all of them' do
    record = policy(all_inboxes: false, inbox_ids: [inbox.id])
    record.update!(all_inboxes: true)

    expect(record.reload.inbox_ids).to eq([])
    expect(record.covers?(create(:inbox, account: account).id)).to be(true)
  end

  it 'is placed last in the list, and the list can be reordered' do
    first = policy(name: 'A')
    second = policy(name: 'B')
    third = policy(name: 'C')
    expect([first, second, third].map { |record| record.reload.position }).to eq([0, 1, 2])

    described_class.reorder!(account, [third.id, first.id])

    expect(described_class.where(account_id: account.id).ordered.map(&:name)).to eq(%w[C A B])
  end

  it 'does not reorder the policies of another account' do
    foreign = described_class.create!(account: create(:account), name: 'Foreign', first_response_seconds: 60)
    own = policy

    described_class.reorder!(account, [foreign.id, own.id])

    expect(foreign.reload.position).to eq(0)
    expect(own.reload.position).to eq(0)
  end

  describe 'the policy a new conversation gets' do
    it 'is the first in the list covering its inbox' do
      policy(name: 'Other inboxes', all_inboxes: false, inbox_ids: [create(:inbox, account: account).id])
      chosen = policy(name: 'Chosen', all_inboxes: false, inbox_ids: [inbox.id])
      policy(name: 'All')

      expect(described_class.covering(create(:conversation, account: account, inbox: inbox))).to eq(chosen)
    end

    it 'is none when the conversation is older than every covering policy' do
      conversation = create(:conversation, account: account, inbox: inbox)
      travel_to(1.minute.from_now) { policy }

      expect(described_class.covering(conversation)).to be_nil
    end
  end
end
