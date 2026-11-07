# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::DiscountPreset do
  let(:account) { create(:account) }
  let(:valid) { { account: account, name: 'Sorry', kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer' } }

  def errors_for(attributes)
    preset = described_class.new(valid.merge(attributes))
    preset.valid?
    preset.errors.details.transform_values { |list| list.pluck(:error) }
  end

  it 'keeps a percentage, an amount, an expiry or none, a number of uses and an audience' do
    expect(described_class.new(valid)).to be_valid
    expect(described_class.new(valid.merge(kind: 'amount', value: '5.00', expires_in_days: nil, usage_limit: 3, audience: 'anyone'))).to be_valid
  end

  it 'reads an empty expiry as never' do
    preset = described_class.create!(valid.merge(expires_in_days: ''))

    expect(preset.expires_in_days).to be_nil
    expect(preset.as_json).to include(expires_in_days: nil, value: '10')
  end

  it 'refuses a value of 0, a percentage above 100 and an amount of 0' do
    expect(errors_for(value: '0')).to include(value: [:greater_than])
    expect(errors_for(value: '100.01')).to include(value: [:less_than_or_equal_to])
    expect(errors_for(value: '100')).not_to have_key(:value)
    expect(errors_for(kind: 'amount', value: '0')).to include(value: [:greater_than])
    expect(errors_for(kind: 'amount', value: '250')).not_to have_key(:value)
  end

  it 'refuses a value finer than a cent' do
    expect(errors_for(value: '10.555')).to include(value: [:invalid])
    expect(errors_for(value: '12.5')).not_to have_key(:value)
  end

  it 'refuses 0 uses, 0 days, a missing name, an unknown kind and an unknown audience' do
    expect(errors_for(usage_limit: 0)).to include(usage_limit: [:greater_than])
    expect(errors_for(expires_in_days: 0)).to include(expires_in_days: [:greater_than])
    expect(errors_for(expires_in_days: 1.5)).to include(expires_in_days: [:not_an_integer])
    expect(errors_for(name: '')).to include(name: [:blank])
    expect(errors_for(name: 'x' * 61)).to include(name: [:too_long])
    expect(errors_for(kind: 'free_shipping')).to include(kind: [:inclusion])
    expect(errors_for(audience: 'vip')).to include(audience: [:inclusion])
  end
end
