# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo product search API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/inclamo/shopify/conversations/#{conversation.display_id}/products" }
  let!(:connection) { create(:inclamo_shopify_connection, account: account, shop_currency: 'UAH') }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def search(query, after: nil, as: agent)
    get url, params: { query: query, after: after }.compact, headers: as.create_new_auth_token
  end

  def search_requests(&block)
    a_request(:post, shopify_graphql_url).with do |request|
      body = JSON.parse(request.body)
      body['query'].match?(/^query product_search\b/) && (!block || block.call(body['variables']))
    end
  end

  it 'finds active products by the beginnings of words or by SKU, with variants, price and availability' do
    stub_shopify_fixture(:product_search, 'product_search_results')

    search('Snow')

    expect(response).to have_http_status(:ok)
    products = response.parsed_body['products']
    expect(products.size).to eq(10)
    expect(products.first).to include('id' => a_string_starting_with('gid://shopify/Product/'), 'title' => 'The Multi-managed Snowboard')
    expect(products.first['variants'].first).to include('title' => nil, 'price' => { 'amount' => '629.95', 'currency' => 'UAH' }, 'available_for_sale' => true)
    expect(response.parsed_body['page']).to eq('has_more' => false, 'cursor' => shopify_fixture('product_search_results').dig('products', 'pageInfo', 'endCursor'))
    expect(search_requests { |variables| variables['query'] == 'status:active AND gift_card:false AND ((Snow*) OR sku:"Snow")' && variables['first'] == 10 }).to have_been_made.once
  end

  it 'marks a sold-out variant as not available for sale' do
    stub_shopify_fixture(:product_search, 'product_search_results')

    search('snow')

    sold_out = response.parsed_body['products'].find { |product| product['title'] == 'The Out of Stock Snowboard' }
    expect(sold_out['variants'].first['available_for_sale']).to be(false)
  end

  it 'answers an empty list when nothing matches' do
    stub_shopify_fixture(:product_search, 'product_search_none')

    search('zzqx')

    expect(response.parsed_body).to eq('products' => [], 'page' => { 'has_more' => false, 'cursor' => nil })
  end

  it 'does not let the text add terms of its own to the store search' do
    stub_shopify_fixture(:product_search, 'product_search_none')

    search('-mug OR "tag:secret" (status:draft)')

    expect(search_requests { |variables| variables['query'] == 'status:active AND gift_card:false AND ((mug* tag* secret* status* draft*) OR sku:"mug tag secret status draft")' }).to have_been_made.once
  end

  it 'asks nothing for an empty text and passes on a cursor for the next page' do
    search('  ')
    expect(response.parsed_body['products']).to eq([])
    expect(search_requests).not_to have_been_made

    stub_shopify_fixture(:product_search, 'product_search_none')
    search('mug', after: 'eyJsYXN0X2lkIjoxfQ==')
    expect(search_requests { |variables| variables['after'] == 'eyJsYXN0X2lkIjoxfQ==' }).to have_been_made.once
  end

  it 'names the missing scope without read_products and does not call the store' do
    connection.update!(scopes: %w[read_customers read_orders write_orders])

    search('mug')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'missing_scope', 'missing_scopes' => ['read_products'])
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'says when no store is connected or the connection is broken' do
    connection.update_columns(status: 'broken') # rubocop:disable Rails/SkipsModelValidations
    search('mug')
    expect(response).to have_http_status(:conflict)

    connection.destroy!
    search('mug')
    expect(response).to have_http_status(:not_found)
  end

  it 'says the store did not answer' do
    stub_request(:post, shopify_graphql_url).to_return(status: 503)

    search('mug')

    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body['error']).to eq('store_unreachable')
  end

  it 'is closed to an agent who cannot see the conversation' do
    search('mug', as: create(:user, account: account, role: :agent))

    expect(response).to have_http_status(:unauthorized)
  end
end
