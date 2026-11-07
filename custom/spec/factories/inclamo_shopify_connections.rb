# frozen_string_literal: true

FactoryBot.define do
  factory :inclamo_shopify_connection, class: 'Inclamo::ShopifyConnection' do
    account
    shop_domain { 'example-store.myshopify.com' }
    shop_name { 'Example Store' }
    shop_currency { 'EUR' }
    auth_kind { 'client_credentials' }
    client_id { 'client-id-for-specs' }
    client_secret { 'client-secret-for-specs' }
    access_token { 'token-for-specs' }
    token_expires_at { 23.hours.from_now }
    scopes { %w[read_customers read_draft_orders read_orders read_products write_draft_orders write_orders] }
    api_version { Inclamo::Shopify::API_VERSION }
    customer_data_mode { 'full' }
    status { 'working' }
    last_checked_at { Time.current }

    trait :legacy do
      auth_kind { 'legacy_token' }
      client_id { nil }
      client_secret { nil }
      access_token { 'legacy-token-for-specs' }
      token_expires_at { nil }
    end

    trait :read_only do
      scopes { %w[read_customers read_orders] }
    end
  end
end
