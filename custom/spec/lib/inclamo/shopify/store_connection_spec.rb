# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::StoreConnection do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:store) { described_class.new(record) }

  shared_examples 'a connection that reads the store' do
    it 'returns the data of a query' do
      stub_shopify(:shop_info, data: shop_info_data)

      expect(store.query(:shop_info).dig('shop', 'name')).to eq('Example Store')
    end
  end

  context 'with client credentials' do
    it_behaves_like 'a connection that reads the store'

    it 'uses the stored token while it is fresh' do
      exchange = stub_token_exchange
      stub_shopify(:shop_info, data: shop_info_data)

      store.query(:shop_info)

      expect(exchange).not_to have_been_requested
    end

    it 'gets a new token by itself once the old one is about to expire' do
      record # created now, so its token is a day old after the jump in time
      exchange = stub_token_exchange(token: 'fresh-token-for-specs')
      fresh = stub_request(:post, shopify_graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'fresh-token-for-specs' })
                                                      .to_return(status: 200, body: { data: shop_info_data }.to_json, headers: ShopifyStubs::JSON_HEADERS)

      travel_to(25.hours.from_now) do
        expect(store.query(:shop_info)).to include('shop')
        expect(record.reload.access_token).to eq('fresh-token-for-specs')
        expect(record.token_expires_at).to be > 23.hours.from_now
      end
      expect(exchange).to have_been_requested.once
      expect(fresh).to have_been_requested.once
    end

    it 'renews five minutes before the expiry, not after it' do
      exchange = stub_token_exchange
      stub_shopify(:shop_info, data: shop_info_data)
      record.update!(token_expires_at: 4.minutes.from_now)

      store.query(:shop_info)

      expect(exchange).to have_been_requested.once
    end

    it 'tries once with a new token when the store refuses the old one' do
      stub_token_exchange(token: 'fresh-token-for-specs')
      stub_request(:post, shopify_graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'token-for-specs' }).to_return(status: 401, body: '{}')
      stub_request(:post, shopify_graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'fresh-token-for-specs' })
                                              .to_return(status: 200, body: { data: shop_info_data }.to_json, headers: ShopifyStubs::JSON_HEADERS)

      expect(store.query(:shop_info)).to include('shop')
      expect(record.reload).to be_working
    end

    it 'marks the connection broken when the credentials are refused, and stops calling the store' do
      refusal = stub_token_refusal('app_not_installed')
      graphql = stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{}')

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Unauthorized)
      expect(record.reload).to be_broken

      expect { described_class.new(record).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::ConnectionBroken)
      expect(graphql).to have_been_requested.once
      expect(refusal).to have_been_requested.once
    end
  end

  context 'with a legacy token' do
    let(:record) { create(:inclamo_shopify_connection, :legacy) }

    it_behaves_like 'a connection that reads the store'

    it 'never asks for a token' do
      exchange = stub_token_exchange
      stub_shopify(:shop_info, data: shop_info_data)

      travel_to(3.days.from_now) { store.query(:shop_info) }

      expect(exchange).not_to have_been_requested
    end

    it 'marks the connection broken on a refused token' do
      stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{}')

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Unauthorized)
      expect(record.reload).to be_broken
    end
  end

  describe '#recheck!' do
    it 'reads the scopes again and repairs a broken connection' do
      record.update!(status: 'broken', scopes: %w[read_customers read_orders])
      stub_token_exchange
      stub_shopify(:shop_info, data: shop_info_data)
      stub_shopify(:customer_data_probe, data: { customers: { nodes: [] } })

      store.recheck!

      expect(record.reload).to be_working
      expect(record.scopes).to include('write_orders')
      expect(record.unavailable_reason('cancel')).to be_nil
    end
  end
end
