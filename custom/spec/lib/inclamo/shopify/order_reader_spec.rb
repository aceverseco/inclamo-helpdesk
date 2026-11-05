# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::OrderReader do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:reader) { described_class.new(record) }
  let(:customer_id) { shopify_fixture('customers_search_one').dig('customers', 'nodes', 0, 'id') }

  before { described_class.forget!(record.account_id) }

  it 'finds a customer by the exact email, whatever its case' do
    stub_shopify_fixture(:customers_search, 'customers_search_one')

    expect(reader.customers_by_email('MAYA.example.t001@example.com').pluck('displayName')).to eq(['Maya Example'])
  end

  it 'does not take a customer whose email only resembles the one asked for' do
    stub_shopify_fixture(:customers_search, 'customers_search_one')

    expect(reader.customers_by_email('example.t001@example.com')).to be_empty
  end

  it 'finds a customer by phone, however it is written' do
    stub_shopify_fixture(:customers_search, 'customers_search_phone')

    expect(reader.customers_by_phone('+1 (500) 555-1011').size).to eq(1)
  end

  it 'keeps a search term from adding terms of its own' do
    request = stub_shopify_fixture(:customers_search, 'customers_search_none')

    reader.customers_by_email('a@example.com" OR email:"b@example.com')

    expect(request.with { |r| JSON.parse(r.body).dig('variables', 'query') == 'email:"a@example.com OR email:b@example.com"' }).to have_been_requested
  end

  it 'reuses an answer for a minute and asks again after an order action' do
    request = stub_shopify_fixture(:customer_orders, 'customer_orders')

    2.times { reader.customer_with_orders(customer_id) }
    expect(request).to have_been_requested.once

    described_class.forget!(record.account_id)
    reader.customer_with_orders(customer_id)
    expect(request).to have_been_requested.twice
  end

  it 'asks again once the minute has passed' do
    request = stub_shopify_fixture(:customer_orders, 'customer_orders')

    reader.customer_with_orders(customer_id)
    expect(Redis::Alfred.ttl(Redis::Alfred.keys("inclamo:shopify:#{record.account_id}:*").find { |key| key.exclude?('generation') })).to be_between(1, 60)
    expect(request).to have_been_requested.once
  end

  it 'does not share answers between accounts' do
    other = described_class.new(create(:inclamo_shopify_connection, shop_domain: 'other-store.myshopify.com'))
    mine = stub_shopify_fixture(:customer_orders, 'customer_orders')
    theirs = stub_shopify(:customer_orders, data: { customer: nil }, domain: 'other-store.myshopify.com')

    reader.customer_with_orders(customer_id)

    expect(other.customer_with_orders(customer_id)).to be_nil
    expect(mine).to have_been_requested.once
    expect(theirs).to have_been_requested.once
  end

  describe 'lookup by order number' do
    it 'finds the order with or without the hash sign' do
      stub_shopify_fixture(:orders_by_number, 'orders_by_number_cancelled')

      expect(reader.order_by_number('#1005')['name']).to eq('#1005')
      expect(reader.order_by_number(' 1005 ')['name']).to eq('#1005')
    end

    it 'returns nothing for a number the store does not have' do
      stub_shopify_fixture(:orders_by_number, 'orders_by_number_none')

      expect(reader.order_by_number('999999')).to be_nil
    end

    it 'does not take an order whose number only contains the one asked for' do
      stub_shopify_fixture(:orders_by_number, 'orders_by_number_cancelled')

      expect(reader.order_by_number('100')).to be_nil
    end

    it 'sends nothing for something that is not an order number' do
      expect(reader.order_by_number('1005" OR name:"1')).to be_nil
      expect(reader.order_by_number('')).to be_nil
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  context 'when the store hides customer data' do
    let(:record) { create(:inclamo_shopify_connection, customer_data_mode: 'limited') }

    it 'never searches customers' do
      expect(reader.customers_by_email('maya.example.t001@example.com')).to be_empty
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'looks an order up without asking for the customer or the address' do
      limited = stub_shopify_fixture(:orders_by_number_limited, 'orders_by_number_limited_open')

      order = reader.order_by_number('1001')

      expect(order).not_to include('customer', 'shippingAddress')
      expect(limited).to have_been_requested.once
    end
  end
end
