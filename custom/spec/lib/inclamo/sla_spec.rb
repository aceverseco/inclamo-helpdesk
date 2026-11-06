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
end
