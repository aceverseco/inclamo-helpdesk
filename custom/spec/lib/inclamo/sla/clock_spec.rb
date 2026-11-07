# frozen_string_literal: true

require 'rails_helper'

# 2026-11-02 is a Monday. Chatwoot gives a new inbox Monday to Friday 9:00 to
# 17:00 and a closed weekend; the specs switch those hours on and change days.
RSpec.describe Inclamo::Sla::Clock do
  let(:account) { create(:account) }
  let(:zone) { ActiveSupport::TimeZone['Europe/Berlin'] }
  let(:inbox) { create(:inbox, account: account, timezone: 'Europe/Berlin', working_hours_enabled: true) }
  let(:clock) { described_class.new(inbox: inbox, business_hours_only: true) }

  def at(text)
    zone.parse(text)
  end

  def day(wday)
    inbox.working_hours.find_by(day_of_week: wday)
  end

  describe 'plain time' do
    let(:clock) { described_class.new(inbox: inbox, business_hours_only: false) }

    it 'counts every second, at night and on the weekend too' do
      expect(clock.elapsed(at('2026-11-07 10:00'), at('2026-11-07 12:30'))).to eq(9_000)
      expect(clock.deadline(at('2026-11-06 16:30'), 7_200)).to eq(at('2026-11-06 18:30'))
      expect(clock.counting_at?(at('2026-11-08 03:00'))).to be(true)
      expect(clock.next_change(at('2026-11-08 03:00'))).to be_nil
    end

    it 'counts real seconds across a change of the clocks' do
      expect(clock.elapsed(at('2026-10-25 00:00'), at('2026-10-26 00:00'))).to eq(25 * 3_600)
    end
  end

  it 'counts every second for an inbox without business hours, whatever the policy says' do
    inbox.update!(working_hours_enabled: false)

    expect(clock.plain?).to be(true)
    expect(clock.elapsed(at('2026-11-07 10:00'), at('2026-11-07 11:00'))).to eq(3_600)
  end

  it 'counts the business hours inside one day' do
    expect(clock.elapsed(at('2026-11-02 10:00'), at('2026-11-02 12:00'))).to eq(7_200)
    expect(clock.elapsed(at('2026-11-02 07:00'), at('2026-11-02 10:00'))).to eq(3_600)
    expect(clock.elapsed(at('2026-11-02 16:00'), at('2026-11-02 20:00'))).to eq(3_600)
  end

  it 'skips the night between two days' do
    expect(clock.elapsed(at('2026-11-02 16:00'), at('2026-11-03 10:00'))).to eq(7_200)
    expect(clock.deadline(at('2026-11-02 16:30'), 7_200)).to eq(at('2026-11-03 10:30'))
  end

  it 'skips the weekend, and a conversation that starts on it waits for Monday' do
    expect(clock.elapsed(at('2026-11-06 16:00'), at('2026-11-09 10:00'))).to eq(7_200)
    expect(clock.deadline(at('2026-11-06 16:00'), 7_200)).to eq(at('2026-11-09 10:00'))
    expect(clock.deadline(at('2026-11-07 12:00'), 3_600)).to eq(at('2026-11-09 10:00'))
    expect(clock.counting_at?(at('2026-11-07 12:00'))).to be(false)
    expect(clock.next_change(at('2026-11-07 12:00'))).to eq(at('2026-11-09 09:00'))
    expect(clock.next_change(at('2026-11-09 10:00'))).to eq(at('2026-11-09 17:00'))
  end

  it 'skips a day the inbox is closed' do
    day(3).update!(closed_all_day: true)

    expect(clock.elapsed(at('2026-11-03 16:00'), at('2026-11-05 10:00'))).to eq(7_200)
    expect(clock.deadline(at('2026-11-03 16:00'), 7_200)).to eq(at('2026-11-05 10:00'))
  end

  it 'counts a whole day for a day open all day' do
    day(6).update!(closed_all_day: false, open_all_day: true)

    expect(clock.elapsed(at('2026-11-06 16:00'), at('2026-11-08 00:00'))).to eq(3_600 + 86_400)
    expect(clock.counting_at?(at('2026-11-07 23:59'))).to be(true)
  end

  it 'counts the real length of a day open all day when the clocks change' do
    day(0).update!(closed_all_day: false, open_all_day: true)

    # 25 October 2026: clocks go back an hour; 29 March 2026: forward an hour.
    expect(clock.elapsed(at('2026-10-25 00:00'), at('2026-10-26 00:00'))).to eq(25 * 3_600)
    expect(clock.elapsed(at('2026-03-29 00:00'), at('2026-03-30 00:00'))).to eq(23 * 3_600)
    expect(clock.deadline(at('2026-10-25 00:00'), 25 * 3_600)).to eq(at('2026-10-26 00:00'))
  end

  it 'keeps business hours in the time zone of the inbox' do
    utc = Time.utc(2026, 11, 2, 8, 0) # 9:00 in Berlin
    expect(clock.counting_at?(utc)).to be(true)
    expect(clock.counting_at?(utc - 1.minute)).to be(false)
  end

  it 'never reaches a deadline when every day is closed' do
    inbox.working_hours.find_each { |hours| hours.update!(closed_all_day: true) }

    expect(clock.deadline(at('2026-11-02 10:00'), 60)).to be_nil
    expect(clock.elapsed(at('2026-11-02 10:00'), at('2026-11-09 10:00'))).to eq(0)
    expect(clock.next_change(at('2026-11-02 10:00'))).to be_nil
  end
end
