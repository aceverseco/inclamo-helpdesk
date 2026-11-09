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

  it 'gives the address form the first and last name and the company as the store keeps them' do
    node = shopify_fixture('order_details_open')['order']
    node['shippingAddress'] = node['shippingAddress'].merge('name' => 'Mary Ann Example', 'firstName' => 'Mary Ann', 'lastName' => 'Example', 'company' => 'Example Works')

    address = described_class.new(node, shop_domain: 'example-store.myshopify.com').as_json[:shipping_address]

    expect(address).to include(first_name: 'Mary Ann', last_name: 'Example', company: 'Example Works')
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

  it 'shows what the order holds and comes to now, after an edit' do
    node = shopify_fixture('order_details_partly_shipped')['order'].deep_dup
    node['currentTotalPriceSet']['shopMoney']['amount'] = '1665.9'
    mug = node.dig('lineItems', 'nodes').find { |line| line['title'].start_with?('E2E Tracked Mug') }
    mug.merge!('currentQuantity' => 1, 'unfulfilledQuantity' => 1)

    order = described_class.new(node, shop_domain: 'example-store.myshopify.com').as_json

    expect(order[:total]).to eq(amount: '1745.9', currency: 'UAH')
    expect(order[:current_total]).to eq(amount: '1665.9', currency: 'UAH')
    expect(order[:items].find { |item| item[:id] == mug['id'] }).to include(quantity: 2, current_quantity: 1)
  end

  it 'offers neither cancellation nor an address change for a cancelled order' do
    order = present('orders_by_number_cancelled', ['orders', 'nodes', 0])

    expect(order[:cancelled_at]).to be_present
    expect(order[:actions]['cancel'][:reason]).to eq('already_cancelled')
    expect(order[:actions]['address'][:reason]).to eq('already_cancelled')
  end

  it "shows the order's tags and note" do
    order = present('customer_orders_marks', ['customer', 'orders', 'nodes', 0])

    expect(order[:tags]).to include('gift', 'priority')
    expect(order[:note]).to eq('Leave at the door')
  end

  it 'shows an order without tags and note as having none' do
    order = described_class.new(shopify_fixture('order_details_open')['order'].merge('tags' => [], 'note' => ''), shop_domain: 'example-store.myshopify.com').as_json

    expect(order).to include(tags: [], note: nil)
  end

  it 'shows no customer and no address when the store hides them' do
    order = present('order_details_limited_open')

    expect(order[:customer]).to be_nil
    expect(order[:shipping_address]).to be_nil
    expect(order[:items].size).to eq(3)
  end
end
