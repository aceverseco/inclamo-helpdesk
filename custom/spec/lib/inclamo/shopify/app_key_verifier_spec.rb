# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

# Verifying a key from the store app before it is used for a connection: the
# scopes are the app's grant, the shop must be the account's, and the store is
# probed for its orders and customers' personal data as for any connection.
RSpec.describe Inclamo::Shopify::Verifier do
  include ShopifyStubs

  let(:domain) { 'example-store.myshopify.com' }
  let(:granted) { %w[write_orders read_orders read_customers] }

  def verify(scopes = granted)
    described_class.call(domain: domain, access_token: 'key-from-the-app', granted_scopes: scopes)
  end

  def shop(domain_answered = domain)
    stub_shopify(:shop_identity, data: { shop: { name: 'Example Store', myshopifyDomain: domain_answered, currencyCode: 'EUR' } })
  end

  it 'takes the granted scopes for a full store and reads no installation' do
    shop
    stub_shopify(:customer_data_probe, data: { orders: { nodes: [] }, customers: { nodes: [] } })

    result = verify

    expect(result).to have_attributes(shop_domain: domain, shop_name: 'Example Store', shop_currency: 'EUR',
                                      scopes: %w[read_customers read_orders write_orders], customer_data_mode: 'full')
    expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |request| request.body.include?('currentAppInstallation') }
  end

  it 'is limited for a store that hides customers from the app' do
    shop
    stub_shopify(:customer_data_probe, errors: access_denied('customers'))

    expect(verify.customer_data_mode).to eq('limited')
  end

  it 'is refused for a store that refuses the app its orders' do
    shop
    stub_shopify(:customer_data_probe, errors: access_denied('orders'))

    expect { verify }.to raise_error(Inclamo::Shopify::Error::OrdersRefused)
  end

  it 'is refused without a read scope, naming it, before the store is asked' do
    expect { verify(%w[read_customers write_orders]) }.to raise_error(Inclamo::Shopify::Error::MissingScopes) { |error|
      expect(error.scopes).to eq(%w[read_orders])
    }
    expect(WebMock).not_to have_requested(:post, shopify_graphql_url)
  end

  it "is refused when the key opens another store than the account's" do
    shop('another-store.myshopify.com')

    expect { verify }.to raise_error(Inclamo::Shopify::Error::OtherStoreKey)
    expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |request| request.body.include?('customer_data_probe') }
  end

  it 'is refused when the store refuses the key' do
    stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{}')

    expect { verify }.to raise_error(Inclamo::Shopify::Error::Unauthorized)
  end
end
