# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Sla do
  it 'checks every minute unless told otherwise' do
    expect(described_class.check_seconds).to eq(60) unless ENV.key?('INCLAMO_SLA_CHECK_SECONDS')
    expect(described_class.check_cron(60)).to eq('* * * * *')
  end

  it 'turns the interval into a cron line, with seconds below a minute' do
    expect(described_class.check_cron(5)).to eq('*/5 * * * * *')
    expect(described_class.check_cron(300)).to eq('*/5 * * * *')
  end

  it 'takes an interval a cron line cannot repeat evenly down to one it can' do
    expect(described_class.check_cron(45)).to eq('*/30 * * * * *')
    expect(described_class.check_cron(7)).to eq('*/6 * * * * *')
    expect(described_class.check_cron(90)).to eq('* * * * *')
    expect(described_class.check_cron(7 * 60)).to eq('*/6 * * * *')
    expect(described_class.check_cron(45 * 60)).to eq('*/30 * * * *')
    expect(described_class.check_cron(3600)).to eq('0 * * * *')
    expect(described_class.check_cron(86_400)).to eq('0 * * * *')

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INCLAMO_SLA_CHECK_SECONDS', 60).and_return('45')
    expect(described_class.check_seconds).to eq(30)
  end

  it 'ignores an interval that is not a positive number' do
    %w[0 -5 soon].each do |value|
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('INCLAMO_SLA_CHECK_SECONDS', 60).and_return(value)

      expect(described_class.check_seconds).to eq(60)
    end
  end

  it 'writes a target in words for the note' do
    expect(described_class.duration_words(7_200)).to eq('2 hours')
    expect(described_class.duration_words(172_800)).to eq('2 days')
    expect(described_class.duration_words(10)).to eq('10 seconds')
  end

  it 'writes long targets in days, as the policies page does, never in weeks or months' do
    expect(described_class.duration_words(30 * 86_400)).to eq('30 days')
    expect(described_class.duration_words(31 * 86_400)).to eq('31 days')
    expect(described_class.duration_words(365 * 86_400)).to eq('365 days')
    expect(described_class.duration_words(86_400 + (4 * 3600))).to eq('1 day and 4 hours')
    expect(described_class.duration_words(5_400)).to eq('1 hour and 30 minutes')
    expect(described_class.duration_words(90_061)).to eq('1 day, 1 hour, 1 minute, and 1 second')
  end
end
