# frozen_string_literal: true

module Inclamo
  # Access to a merchant's Shopify store through the Admin GraphQL API.
  module Shopify
    DOCUMENTS_DIR = Overlay::ROOT.join('graphql/shopify')
    # One pinned API version for every request. Bumping it is part of the
    # routine for a new Chatwoot release: change the file, run the schema check.
    API_VERSION = DOCUMENTS_DIR.join('API_VERSION').read.strip.freeze
    DOMAIN_FORMAT = /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/

    def self.valid_domain?(domain)
      domain.is_a?(String) && domain.match?(DOMAIN_FORMAT)
    end

    # The page of an order or a draft (`kind`: orders, draft_orders) in the
    # store's admin. `id` is its number or its global id.
    def self.admin_url(shop_domain, kind, id)
      "https://admin.shopify.com/store/#{shop_domain.to_s.delete_suffix('.myshopify.com')}/#{kind}/#{id.to_s.split('/').last}"
    end

    # Where requests for a shop go. Always the shop itself, except in the
    # end-to-end environment, where a proxy that the tests control stands in
    # front of Shopify. Both variables must be set for that; one alone is ignored.
    def self.base_url(domain)
      override = ENV.fetch('INCLAMO_SHOPIFY_BASE_URL', nil)
      return override if override.present? && ENV['INCLAMO_E2E'] == '1'

      "https://#{domain}"
    end
  end
end
