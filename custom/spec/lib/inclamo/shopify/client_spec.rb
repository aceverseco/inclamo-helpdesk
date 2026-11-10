# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Shopify::Client do
  let(:domain) { 'example-store.myshopify.com' }
  let(:url) { "https://#{domain}/admin/api/#{Inclamo::Shopify::API_VERSION}/graphql.json" }
  let(:waits) { [] }
  let(:client) { described_class.new(domain: domain, access_token: 'token-for-specs', sleeper: ->(seconds) { waits << seconds }) }
  let(:shop_answer) { { data: { shop: { name: 'Example Store' } } }.to_json }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def throttled(requested:, available:, rate:)
    {
      errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }],
      extensions: { cost: { requestedQueryCost: requested, throttleStatus: { currentlyAvailable: available, restoreRate: rate } } }
    }.to_json
  end

  it 'sends the document with the token and returns the data' do
    request = stub_request(:post, url)
              .with(headers: { 'X-Shopify-Access-Token' => 'token-for-specs', 'X-Shopify-Shop-Domain' => domain })
              .to_return(status: 200, body: shop_answer, headers: json)

    expect(client.query(:shop_info)).to eq('shop' => { 'name' => 'Example Store' })
    expect(request).to have_been_requested.once
    expect(WebMock).to(have_requested(:post, url).with { |r| JSON.parse(r.body)['query'].include?('query shop_info') })
  end

  it 'waits as long as the store states when throttled, then succeeds' do
    stub_request(:post, url).to_return(
      { status: 200, body: throttled(requested: 120, available: 20, rate: 50), headers: json },
      { status: 200, body: shop_answer, headers: json }
    )

    expect(client.query(:shop_info)).to include('shop')
    expect(waits).to eq([2.0])
  end

  it 'honours Retry-After on a 429' do
    stub_request(:post, url).to_return(
      { status: 429, headers: { 'Retry-After' => '3' } },
      { status: 200, body: shop_answer, headers: json }
    )

    client.query(:shop_info)

    expect(waits).to eq([3.0])
  end

  it 'gives up when the stated wait does not fit the time limit' do
    stub_request(:post, url).to_return(status: 200, body: throttled(requested: 1000, available: 0, rate: 50), headers: json)

    expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Throttled)
    expect(waits).to be_empty
  end

  it 'reports a timeout as an unknown outcome and does not retry' do
    request = stub_request(:post, url).to_timeout

    expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Timeout) { |error| expect(error.outcome_unknown?).to be(true) }
    expect(request).to have_been_requested.once
  end

  it 'reports a store it could not connect to as not reached: the request was never sent' do
    [SocketError, Net::OpenTimeout, Errno::ECONNREFUSED].each do |failure|
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |http| allow(http).to receive(:start).and_raise(failure) }
      end
      request = stub_request(:post, url).to_return(status: 200, body: shop_answer, headers: json)

      expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Unreachable) { |error| expect(error.outcome_unknown?).to be(false) }
      expect(request).not_to have_been_requested
    end
  end

  it 'reports a refused token' do
    stub_request(:post, url).to_return(status: 401, body: '{"errors":"[API] Invalid API key or access token"}')

    expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Unauthorized)
  end

  it 'reports a server error of the store as an unknown outcome' do
    stub_request(:post, url).to_return(status: 503, body: 'upstream error')

    expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Unavailable) { |error| expect(error.outcome_unknown?).to be(true) }
  end

  it 'reports a missing shop' do
    stub_request(:post, url).to_return(status: 404, body: '{"errors":"Not Found"}')

    expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::ShopUnavailable)
  end

  it 'reports GraphQL errors with their codes' do
    body = { errors: [{ message: 'Access denied for customer field.', extensions: { code: 'ACCESS_DENIED' } }] }.to_json
    stub_request(:post, url).to_return(status: 200, body: body, headers: json)

    expect { client.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::QueryError) do |error|
      expect(error.access_denied?).to be(true)
      expect(error.outcome_unknown?).to be(false)
    end
  end

  it 'refuses a domain that is not a myshopify.com domain' do
    ['example.com', 'evil.com/x.myshopify.com', 'a.myshopify.com.evil.com', 'UPPER.myshopify.com', nil].each do |bad|
      expect { described_class.new(domain: bad, access_token: 'x') }.to raise_error(ArgumentError)
    end
  end

  it 'refuses a document it does not know' do
    expect { client.query(:no_such_document) }.to raise_error(Inclamo::Shopify::Documents::Unknown)
  end

  describe 'where requests go' do
    it 'is the shop itself, also when only the override is set' do
      with_modified_env INCLAMO_SHOPIFY_BASE_URL: 'http://proxy:8080', INCLAMO_E2E: nil do
        expect(Inclamo::Shopify.base_url(domain)).to eq("https://#{domain}")
      end
    end

    it 'is the proxy in the end-to-end environment' do
      with_modified_env INCLAMO_SHOPIFY_BASE_URL: 'http://proxy:8080', INCLAMO_E2E: '1' do
        expect(Inclamo::Shopify.base_url(domain)).to eq('http://proxy:8080')
      end
    end
  end
end
