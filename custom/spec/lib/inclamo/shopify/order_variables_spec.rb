# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderVariables do
  def variables(fixture, path = %w[order])
    described_class.new(shopify_fixture(fixture).dig(*path)).to_h
  end

  it 'states every fact of a shipped order' do
    expect(variables('order_details_shipped')).to eq(
      'number' => '#1002',
      'date' => 'November 5, 2026',
      'total' => '1,585.90 UAH',
      'payment_status' => 'Paid',
      'fulfillment_status' => 'Shipped',
      'tracking_number' => 'E2Et001A',
      'tracking_link' => 'https://example.com/track/E2Et001A',
      'status_link' => shopify_fixture('order_details_shipped').dig('order', 'statusPageUrl'),
      'items' => "1 × The Minimal Snowboard\n1 × The Complete Snowboard"
    )
  end

  it 'has a value under every name, empty for what the order does not have' do
    open_order = variables('order_details_open')

    expect(open_order.keys).to eq(described_class::NAMES)
    expect(open_order).to include('tracking_number' => '', 'tracking_link' => '', 'fulfillment_status' => 'Not shipped')
    expect(open_order['items'].lines.size).to eq(3)
    expect(open_order['status_link']).to start_with('https://')
  end

  it 'needs nothing the store hides in the limited mode' do
    limited = variables('order_details_limited_open')

    expect(limited.except('tracking_number', 'tracking_link').values).to all(be_present)
  end

  it 'writes the total with the decimal places of its currency' do
    total = lambda do |amount, currency|
      described_class.new('totalPriceSet' => { 'shopMoney' => { 'amount' => amount, 'currencyCode' => currency } }).total
    end

    expect(total.call('54.0', 'EUR')).to eq('54.00 EUR')
    expect(total.call('5400.0', 'JPY')).to eq('5,400 JPY')
    expect(total.call('12.5', 'KWD')).to eq('12.500 KWD')
  end
end
