# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Sla::Urgency do
  cases = JSON.parse(Rails.root.join('custom/spec/fixtures/sla_urgency_cases.json').read)['cases']

  # The same cases are run by the dashboard's test of the badge (slaBadgeRule.spec.js).
  cases.each do |one|
    it "agrees with the badge: #{one['name']}" do
      expect(described_class.of(one['timer'])).to eq(one['expect'])
    end
  end

  it 'starts "soon" at the last quarter of the target, five minutes at least, the whole of a shorter target' do
    expect(described_class.soon_from(86_400)).to eq(21_600)
    expect(described_class.soon_from(900)).to eq(300)
    expect(described_class.soon_from(120)).to eq(120)
  end

  describe '.level' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:timer) do
      Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 900, resolution_seconds: 86_400)
      Inclamo::Sla::Timers.apply!(conversation)
    end

    it 'counts a conversation under overdue, soon or other as its timer stands at that moment' do
      start = timer.started_at

      expect(described_class.level(timer, now: start + 5.minutes)).to eq('other')
      expect(described_class.level(timer, now: start + 11.minutes)).to eq('soon')
      expect(described_class.level(timer, now: start + 16.minutes)).to eq('overdue')
      expect(described_class.level(nil)).to eq('other')
    end

    it 'counts a replied conversation under other until its resolution is soon' do
      timer.update!(first_response_at: timer.started_at + 2.minutes)

      expect(described_class.level(timer, now: timer.started_at + 1.hour)).to eq('other')
      expect(described_class.level(timer, now: timer.started_at + 19.hours)).to eq('soon')
      expect(described_class.level(timer, now: timer.started_at + 25.hours)).to eq('overdue')
    end
  end
end
