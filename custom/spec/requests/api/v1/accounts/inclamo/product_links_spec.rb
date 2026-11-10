# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo product search, storefront links', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}/products" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inclamo_shopify_connection, account: account, shop_currency: 'UAH')
  end

  # Recorded on a development store: it is password-protected, so the store
  # gives no storefront link even for the published "Shown Mug".
  it 'gives no storefront link for a product the store gives none' do
    stub_shopify_fixture(:product_search, 'product_search_storefront')

    get url, params: { query: 'E2E r0001' }, headers: agent.create_new_auth_token

    expect(response.parsed_body['products'].pluck('title', 'online_store_url')).to eq([['E2E r0001 Hidden Mug', nil], ['E2E r0001 Shown Mug', nil]])
    expect(a_request(:post, shopify_graphql_url).with { |request| JSON.parse(request.body)['query'].include?('onlineStoreUrl') }).to have_been_made.once
  end

  it 'gives the storefront link of a product in the online store of an open store' do
    results = shopify_fixture('product_search_storefront')
    shown = results.dig('products', 'nodes').find { |node| node['title'].end_with?('Shown Mug') }
    shown['onlineStoreUrl'] = 'https://shop.example.com/products/e2e-r0001-shown-mug'
    stub_shopify(:product_search, data: results)

    get url, params: { query: 'E2E r0001' }, headers: agent.create_new_auth_token

    expect(response.parsed_body['products'].pluck('title', 'online_store_url'))
      .to eq([['E2E r0001 Hidden Mug', nil], ['E2E r0001 Shown Mug', 'https://shop.example.com/products/e2e-r0001-shown-mug']])
  end
end
