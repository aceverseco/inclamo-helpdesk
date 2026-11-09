# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::StatusWords do
  # Every order of the recorded answers, whatever document it came from.
  def recorded_orders(value = Dir[Rails.root.join('custom/spec/fixtures/shopify/*.json')].map { |file| JSON.parse(File.read(file)) })
    case value
    when Array then value.flat_map { |item| recorded_orders(item) }
    when Hash then (value.key?('displayFinancialStatus') ? [value] : []) + value.values.flat_map { |item| recorded_orders(item) }
    else []
    end
  end

  it 'gives the panel and the reply variables the same words for every recorded status' do
    orders = recorded_orders
    expect(orders.size).to be > 5

    orders.each do |node|
      panel = Inclamo::Shopify::OrderPresenter.new(node, shop_domain: 'example-store.myshopify.com').as_json
      variables = Inclamo::Shopify::OrderVariables.new(node).to_h

      expect(panel[:financial_status_text]).to eq(variables['payment_status']).and be_present
      expect(panel[:fulfillment_status_text]).to eq(variables['fulfillment_status']).and be_present
    end
  end

  it 'keeps the words the panel has always shown' do
    words = { 'PAID' => 'Paid', 'PENDING' => 'Payment pending', 'PARTIALLY_REFUNDED' => 'Partially refunded', 'REFUNDED' => 'Refunded',
              'FULFILLED' => 'Shipped', 'UNFULFILLED' => 'Not shipped', 'PARTIALLY_FULFILLED' => 'Partially shipped', 'ON_HOLD' => 'On hold' }

    words.each { |status, text| expect(described_class.for(status)).to eq(text) }
    # Recorded from a cancelled order; the table has no entry for it.
    expect(described_class.for('FULFILLMENT_NOT_REQUIRED')).to eq('Fulfillment not required')
  end

  it 'says the same in whatever language the request runs' do
    I18n.with_locale(:de) { expect(described_class.for('FULFILLED')).to eq('Shipped') }
  end

  it 'shows a status it does not know as plain words' do
    expect(described_class.for('SOMETHING_NEW')).to eq('Something new')
    expect(described_class.for(nil)).to eq('')
    expect(described_class.for('fulfilled')).to eq('Shipped')
  end
end
