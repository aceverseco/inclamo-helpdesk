# frozen_string_literal: true

module Inclamo
  module Shopify
    # Checks credentials against a store before anything is saved, and again on
    # "check again": gets a token, reads the shop and the scopes the app holds,
    # and learns whether the store gives the app its orders and customers'
    # personal data.
    class Verifier
      Result = Struct.new(:shop_domain, :shop_name, :shop_currency, :scopes, :customer_data_mode,
                          :access_token, :token_expires_at, keyword_init: true)

      def self.normalize_domain(value)
        value.to_s.strip.downcase.sub(%r{\Ahttps?://}, '').sub(%r{/.*\z}, '')
      end

      # Give either client_id and client_secret, or access_token (legacy app).
      def self.call(domain:, client_id: nil, client_secret: nil, access_token: nil)
        domain = normalize_domain(domain)
        raise Error::InvalidDomain, 'not a myshopify.com domain' unless Shopify.valid_domain?(domain)

        expires_at = nil
        if access_token.blank?
          exchange = TokenExchange.call(domain: domain, client_id: client_id, client_secret: client_secret)
          access_token = exchange.access_token
          expires_at = exchange.expires_at
        end

        client = Client.new(domain: domain, access_token: access_token)
        info = client.query(:shop_info)
        scopes = Array(info.dig('currentAppInstallation', 'accessScopes')).pluck('handle').sort
        missing = ShopifyConnection::READ_SCOPES - scopes
        raise Error::MissingScopes, missing if missing.any?

        Result.new(
          shop_domain: info.dig('shop', 'myshopifyDomain') || domain,
          shop_name: info.dig('shop', 'name'),
          shop_currency: info.dig('shop', 'currencyCode'),
          scopes: scopes,
          customer_data_mode: customer_data_mode(client),
          access_token: access_token,
          token_expires_at: expires_at
        )
      end

      def self.customer_data_mode(client)
        client.query(:customer_data_probe)
        'full'
      rescue Error::QueryError => e
        raise unless e.access_denied?
        raise Error::OrdersRefused, e.message if e.paths.include?('orders')

        'limited'
      end
      private_class_method :customer_data_mode
    end
  end
end
