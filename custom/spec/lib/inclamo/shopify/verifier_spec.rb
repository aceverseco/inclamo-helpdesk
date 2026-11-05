# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::Verifier do
  let(:credentials) { { domain: 'example-store.myshopify.com', client_id: 'client-id', client_secret: 'client-secret' } }

  def stub_full_store(scopes: nil)
    stub_token_exchange
    stub_shopify(:shop_info, data: scopes ? shop_info_data(scopes: scopes) : shop_info_data)
    stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })
  end

  it 'accepts valid client credentials and reports the store' do
    stub_full_store

    result = described_class.call(**credentials)

    expect(result.to_h).to include(shop_domain: 'example-store.myshopify.com', shop_name: 'Example Store', shop_currency: 'EUR',
                                   customer_data_mode: 'full', access_token: 'fresh-token-for-specs')
    expect(result.scopes).to include('read_orders', 'write_orders')
    expect(result.token_expires_at).to be_within(1.minute).of(24.hours.from_now)
  end

  it 'accepts a legacy token without asking for another' do
    exchange = stub_token_exchange
    stub_shopify(:shop_info, data: shop_info_data)
    stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

    result = described_class.call(domain: 'example-store.myshopify.com', access_token: 'legacy-token')

    expect(result.access_token).to eq('legacy-token')
    expect(result.token_expires_at).to be_nil
    expect(exchange).not_to have_been_requested
  end

  it 'accepts a domain pasted as an address' do
    stub_full_store

    expect(described_class.call(**credentials, domain: ' HTTPS://Example-Store.myshopify.com/admin ').shop_domain).to eq('example-store.myshopify.com')
  end

  it 'reports an app that is not installed on the store' do
    stub_token_refusal('app_not_installed')

    expect { described_class.call(**credentials) }.to raise_error(Inclamo::Shopify::Error::AppNotInstalled)
  end

  it 'reports refused credentials' do
    stub_token_refusal('invalid_request')

    expect { described_class.call(**credentials) }.to raise_error(Inclamo::Shopify::Error::CredentialsRefused)
  end

  it 'reports a refused legacy token' do
    stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{}')

    expect { described_class.call(domain: 'example-store.myshopify.com', access_token: 'revoked') }.to raise_error(Inclamo::Shopify::Error::Unauthorized)
  end

  it 'sends nothing for a domain that is not a Shopify store domain' do
    expect { described_class.call(**credentials, domain: 'shop.example.com') }.to raise_error(Inclamo::Shopify::Error::InvalidDomain)
    expect(WebMock).not_to have_requested(:any, /.*/)
  end

  it 'names the read scope the app lacks' do
    stub_full_store(scopes: %w[read_customers])

    expect { described_class.call(**credentials) }.to raise_error(Inclamo::Shopify::Error::MissingScopes) { |error| expect(error.scopes).to eq(%w[read_orders]) }
  end

  it 'reports the limited mode when the store hides customer data' do
    stub_token_exchange
    stub_shopify(:shop_info, data: shop_info_data)
    stub_shopify(:customer_data_probe, errors: access_denied)

    expect(described_class.call(**credentials).customer_data_mode).to eq('limited')
  end

  it 'reports an app the store refuses its orders' do
    stub_token_exchange
    stub_shopify(:shop_info, data: shop_info_data)
    stub_shopify(:customer_data_probe, errors: access_denied('orders'))

    expect { described_class.call(**credentials) }.to raise_error(Inclamo::Shopify::Error::OrdersRefused)
  end

  it 'asks for orders before customers, because the store names only its first refusal' do
    document = Inclamo::Shopify::Documents.fetch(:customer_data_probe)

    expect(document.index('orders(')).to be < document.index('customers(')
  end
end
