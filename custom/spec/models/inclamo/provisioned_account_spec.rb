# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::ProvisionedAccount do
  let(:account) { create(:account) }

  it 'keeps the domain lower-case and finds a store whatever the case of the letters' do
    row = described_class.create!(shop_domain: ' Example-Store.MyShopify.com ', account: account)

    expect(row.reload.shop_domain).to eq('example-store.myshopify.com')
    expect(described_class.for_store('EXAMPLE-STORE.myshopify.com')).to eq(row)
    expect(row).to be_active
  end

  it 'has the database refuse a domain that is not lower-case' do
    row = described_class.create!(shop_domain: 'example-store.myshopify.com', account: account)

    expect { row.update_columns(shop_domain: 'Example-Store.myshopify.com') }.to raise_error(ActiveRecord::StatementInvalid, /domain_lower/)
  end

  it 'keeps one row per store, by the unique index alone' do
    described_class.create!(shop_domain: 'example-store.myshopify.com', account: account)
    again = described_class.new(shop_domain: 'EXAMPLE-store.myshopify.com', account: create(:account))

    expect(again).to be_valid
    expect { again.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'keeps one store per account, by the unique index alone' do
    described_class.create!(shop_domain: 'example-store.myshopify.com', account: account)
    again = described_class.new(shop_domain: 'other-store.myshopify.com', account: account)

    expect { again.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'accepts only a myshopify.com domain and a known state' do
    ['example.com', 'shop.example.com', 'evil.myshopify.com.example.com', '-a.myshopify.com', 'a b.myshopify.com', ''].each do |domain|
      expect(described_class.new(shop_domain: domain, account: account)).not_to be_valid
    end
    expect(described_class.new(shop_domain: 'a.myshopify.com', account: account, state: 'gone')).not_to be_valid
    expect do
      described_class.create!(shop_domain: 'a.myshopify.com', account: account).update_columns(state: 'gone')
    end.to raise_error(ActiveRecord::StatementInvalid, /state/)
  end

  it 'has its storefront inbox emptied by the database when the inbox is destroyed, and stays itself' do
    inbox = create(:channel_widget, account: account).inbox
    row = described_class.create!(shop_domain: 'example-store.myshopify.com', account: account, storefront_inbox: inbox)
    expect(row.reload.storefront_inbox).to eq(inbox)

    inbox.destroy!

    expect(row.reload).to have_attributes(storefront_inbox_id: nil, storefront_inbox: nil, account_id: account.id, state: 'active')
    foreign_key = described_class.connection.foreign_keys(described_class.table_name).find { |key| key.column == 'storefront_inbox_id' }
    expect(foreign_key).to have_attributes(to_table: 'inboxes', on_delete: :nullify)
  end

  it 'keeps an inbox as the storefront inbox of one account only' do
    inbox = create(:channel_widget, account: account).inbox
    described_class.create!(shop_domain: 'example-store.myshopify.com', account: account, storefront_inbox: inbox)
    again = described_class.new(shop_domain: 'other-store.myshopify.com', account: create(:account), storefront_inbox: inbox)

    expect { again.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'goes with its account and has indexes for both lookups' do
    described_class.create!(shop_domain: 'example-store.myshopify.com', account: account)
    indexes = described_class.connection.indexes(described_class.table_name)

    expect(indexes.select(&:unique).map(&:columns)).to contain_exactly(['shop_domain'], ['account_id'], ['storefront_inbox_id'])
    expect { Account.where(id: account.id).delete_all }.to change(described_class, :count).by(-1)
  end
end
