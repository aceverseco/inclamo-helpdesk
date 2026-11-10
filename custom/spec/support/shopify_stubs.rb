# frozen_string_literal: true

# Stubs of the two Shopify endpoints the overlay calls, for specs.
module ShopifyStubs
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  def shopify_graphql_url(domain = 'example-store.myshopify.com')
    "https://#{domain}/admin/api/#{Inclamo::Shopify::API_VERSION}/graphql.json"
  end

  def shopify_token_url(domain = 'example-store.myshopify.com')
    "https://#{domain}/admin/oauth/access_token"
  end

  def stub_token_exchange(domain: 'example-store.myshopify.com', token: 'fresh-token-for-specs', expires_in: 86_399)
    stub_request(:post, shopify_token_url(domain))
      .to_return(status: 200, body: { access_token: token, scope: 'read_customers,write_orders', expires_in: expires_in }.to_json, headers: JSON_HEADERS)
  end

  def stub_token_refusal(reason, domain: 'example-store.myshopify.com')
    stub_request(:post, shopify_token_url(domain))
      .to_return(status: 400, body: "<html><head><title>400 - Oauth error #{reason}</title></head></html>")
  end

  # Answers a GraphQL operation by its name with `data`, or with `errors`.
  def stub_shopify(operation, data: nil, errors: nil, status: 200, domain: 'example-store.myshopify.com')
    body = errors ? { errors: errors } : { data: data }
    stub_request(:post, shopify_graphql_url(domain))
      .with { |request| JSON.parse(request.body)['query'].match?(/^(query|mutation) #{operation}\b/) }
      .to_return(status: status, body: body.to_json, headers: JSON_HEADERS)
  end

  # The store's proposal for refunding `order`: `amount` back through one
  # manual payment, `shipping` of the order's shipping left to refund. With a
  # block, only for the requests whose variables the block accepts.
  def stub_refund_suggestion(order, amount:, shipping: '0.0', &matching)
    currency = order['currencyCode']
    money = ->(value) { { shopMoney: { amount: value, currencyCode: currency } } }
    total = money.call(order.dig('totalPriceSet', 'shopMoney', 'amount'))
    suggestion = {
      amountSet: money.call(amount), maximumRefundableSet: total,
      shipping: { amountSet: money.call(shipping), maximumRefundableSet: money.call(shipping) },
      refundLineItems: order.dig('lineItems', 'nodes').map { |line| { lineItem: { id: line['id'] }, quantity: line['quantity'], restockType: 'NO_RESTOCK' } },
      suggestedTransactions: [{ gateway: 'manual', formattedGateway: 'Manual', kind: 'SUGGESTED_REFUND', amountSet: money.call(amount), maximumRefundableSet: total,
                                parentTransaction: { id: 'gid://shopify/OrderTransaction/1' } }]
    }
    body = { data: { order: { id: order['id'], name: order['name'], currencyCode: currency, suggestedRefund: suggestion } } }
    stub_request(:post, shopify_graphql_url)
      .with do |request|
        sent = JSON.parse(request.body)
        sent['query'].match?(/^query refund_suggestion\b/) && (matching.nil? || matching.call(sent['variables']))
      end
      .to_return(status: 200, body: body.to_json, headers: JSON_HEADERS)
  end

  def shop_info_data(scopes: %w[read_customers read_orders write_orders write_draft_orders read_draft_orders read_products write_order_edits read_order_edits])
    {
      shop: { name: 'Example Store', myshopifyDomain: 'example-store.myshopify.com', currencyCode: 'EUR',
              plan: { publicDisplayName: 'Grow', partnerDevelopment: false } },
      currentAppInstallation: { accessScopes: scopes.map { |handle| { handle: handle } } }
    }
  end

  # An answer recorded from a development store, scrubbed of nothing because
  # the store holds only invented people. See custom/spec/fixtures/shopify.
  def shopify_fixture(name)
    JSON.parse(Rails.root.join('custom/spec/fixtures/shopify', "#{name}.json").read)['data']
  end

  def stub_shopify_fixture(operation, name)
    stub_shopify(operation, data: shopify_fixture(name))
  end

  # The store's refusal of a root field, as recorded from a development store.
  def access_denied(field = 'customers')
    object = { 'customers' => 'Customer', 'orders' => 'Order' }.fetch(field)
    [{ message: "This app is not approved to access the #{object} object. See https://shopify.dev/docs/apps/launch/protected-customer-data for more details.",
       path: [field], extensions: { code: 'ACCESS_DENIED' } }]
  end
end

RSpec.configure { |config| config.include ShopifyStubs }
