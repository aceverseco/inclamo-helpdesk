# frozen_string_literal: true

module Inclamo
  module Shopify
    # The store's catalogue as an agent searches it from a conversation: active
    # products that are not gift cards, by the beginnings of the words of their
    # title or by SKU, with their variants, price and whether they can be sold.
    # One search for every dialog that picks a product.
    class ProductSearch
      SCOPES = %w[read_products].freeze
      PAGE = 10
      MAX_LENGTH = 100
      MAX_WORDS = 8
      CURSOR = %r{\A[A-Za-z0-9+/=_-]{1,500}\z}
      DEFAULT_VARIANT = 'Default Title'
      OPERATORS = %w[AND OR NOT].freeze

      def initialize(connection)
        @connection = connection
      end

      def missing_scopes
        SCOPES - @connection.scopes
      end

      # { products: [...], page: { has_more:, cursor: } }. An empty text finds nothing and asks nothing.
      def call(text, after: nil)
        words = self.class.words(text)
        return { products: [], page: { has_more: false, cursor: nil } } if words.empty?

        after = after.to_s.match?(CURSOR) ? after.to_s : nil
        answer = StoreConnection.new(@connection).query(:product_search, { query: self.class.query(words), first: PAGE, after: after })['products']
        {
          products: Array(answer['nodes']).map { |node| self.class.present_product(node, currency: @connection.shop_currency) },
          page: { has_more: answer.dig('pageInfo', 'hasNextPage') || false, cursor: answer.dig('pageInfo', 'endCursor') }
        }
      end

      # The agent's text without what the store's search syntax would read as its own.
      def self.words(text)
        text.to_s.first(MAX_LENGTH).gsub(/["'`\\():*<>=]/, ' ').split
            .map { |word| word.sub(/\A-+/, '') }.reject { |word| word.blank? || OPERATORS.include?(word) }.first(MAX_WORDS)
      end

      def self.query(words)
        prefixes = words.map { |word| "#{word}*" }.join(' ')
        %(status:active AND gift_card:false AND ((#{prefixes}) OR sku:"#{words.join(' ')}"))
      end

      def self.present_product(node, currency:)
        # online_store_url: the storefront link; nil when the product is not published in the online store.
        product = { id: node['id'], title: node['title'], image_url: node.dig('featuredMedia', 'preview', 'image', 'url'), online_store_url: node['onlineStoreUrl'] }
        variants = node.dig('variants', 'nodes')
        variants ? product.merge(variants: variants.map { |variant| present_variant(variant, currency: currency) }) : product
      end

      # A variant; its title is empty when the product has only the default one.
      def self.present_variant(node, currency:)
        {
          id: node['id'], title: (node['title'] unless node['title'] == DEFAULT_VARIANT), sku: node['sku'],
          price: { amount: node['price'], currency: currency }, available_for_sale: node['availableForSale'] == true
        }
      end
    end
  end
end
