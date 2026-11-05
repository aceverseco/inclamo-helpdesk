# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderPresenter do
  def present(fixture, path = %w[order])
    described_class.new(shopify_fixture(fixture).dig(*path), shop_domain: 'example-store.myshopify.com').as_json
  end

  it 'shows an order shipped in two parcels with both shipments' do
    order = present('order_details_shipped')

    expect(order[:shipments].size).to eq(2)
    expect(order[:shipments].map { |shipment| shipment[:tracking].first }).to all(include(:company, :number, :url))
    expect(order[:shipments].flat_map { |shipment| shipment[:tracking].pluck(:company) }).to eq(['DHL Express', 'UPS'])
    expect(order[:actions]['address']).to eq(allowed: false, reason: 'already_shipped')
    expect(order[:shipping_address]).to include(city: 'Springfield', country_code: 'US')
  end

  it 'shows what was refunded and what remains refundable' do
    order = present('order_details_refunded')

    expect(order[:financial_status]).to eq('PARTIALLY_REFUNDED')
    expect(order[:refunded][:amount].to_d).to eq(20)
    expect(order[:refundable][:amount].to_d).to eq(order[:total][:amount].to_d - 20)
    expect(order[:refunds].size).to eq(1)
    expect(order[:actions]['refund']).to eq(allowed: true, reason: nil)
  end

  it 'shows an open order with its items and every action' do
    order = present('order_details_open')

    expect(order[:items].size).to eq(3)
    expect(order[:items]).to all(include(:title, :quantity, :unit_price))
    expect(order[:number]).to start_with('#')
    expect(order[:admin_url]).to match(%r{\Ahttps://admin\.shopify\.com/store/example-store/orders/\d+\z})
    expect(order[:actions].values).to all(eq(allowed: true, reason: nil))
  end

  it 'offers neither cancellation nor an address change for a cancelled order' do
    order = present('orders_by_number_cancelled', ['orders', 'nodes', 0])

    expect(order[:cancelled_at]).to be_present
    expect(order[:actions]['cancel'][:reason]).to eq('already_cancelled')
    expect(order[:actions]['address'][:reason]).to eq('already_cancelled')
  end

  it 'shows no customer and no address when the store hides them' do
    order = present('order_details_limited_open')

    expect(order[:customer]).to be_nil
    expect(order[:shipping_address]).to be_nil
    expect(order[:items].size).to eq(3)
  end
end
