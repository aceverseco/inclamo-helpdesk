# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::ShopifyConnection do
  it 'allows one connection per account' do
    first = create(:inclamo_shopify_connection)
    second = build(:inclamo_shopify_connection, account: first.account, shop_domain: 'other-store.myshopify.com')

    expect(second).not_to be_valid
    expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'keeps the secret and the token encrypted at rest' do
    record = create(:inclamo_shopify_connection)
    row = described_class.connection.select_one("SELECT client_secret, access_token FROM inclamo_shopify_connections WHERE id = #{record.id}")

    expect(row['client_secret']).not_to include('client-secret-for-specs')
    expect(row['access_token']).not_to include('token-for-specs')
    expect(record.reload.client_secret).to eq('client-secret-for-specs')
    expect(record.access_token).to eq('token-for-specs')
  end

  it 'is refused on an installation without encryption keys' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

    record = build(:inclamo_shopify_connection)

    expect(record).not_to be_valid
    expect(record.errors[:base].join).to include('encryption')
  end

  it 'accepts only a myshopify.com domain' do
    expect(build(:inclamo_shopify_connection, shop_domain: 'shop.example.com')).not_to be_valid
  end

  it 'needs a secret for client credentials and a token for a legacy app' do
    expect(build(:inclamo_shopify_connection, client_secret: nil)).not_to be_valid
    expect(build(:inclamo_shopify_connection, :legacy, access_token: nil)).not_to be_valid
    expect(build(:inclamo_shopify_connection, :legacy)).to be_valid
  end

  describe 'actions' do
    it 'are all available with the write scopes' do
      record = build(:inclamo_shopify_connection)
      report = record.tap { record.scopes += %w[write_discounts] }.actions_report

      expect(report.pluck(:name)).to eq(%w[cancel refund address replacement new_order discount])
      expect(report).to all(include(available: true, reason: nil, missing_scopes: []))
    end

    it 'name the missing scope with a read-only app' do
      report = build(:inclamo_shopify_connection, :read_only).actions_report.index_by { |action| action[:name] }

      expect(report['cancel']).to include(available: false, reason: 'missing_scope', missing_scopes: %w[write_orders])
      expect(report['replacement'][:missing_scopes]).to eq(%w[write_orders write_draft_orders read_products])
    end

    it 'exclude the address change when the store hides customer data' do
      record = build(:inclamo_shopify_connection, customer_data_mode: 'limited')

      expect(record.unavailable_reason('address')).to eq('customer_data_hidden')
      expect(record.unavailable_reason('refund')).to be_nil
    end
  end
end
