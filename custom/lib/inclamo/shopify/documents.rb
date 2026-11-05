# frozen_string_literal: true

module Inclamo
  module Shopify
    # The GraphQL documents we send, one operation per file in
    # custom/graphql/shopify. They are files so that CI can validate each one
    # against the published schema of the pinned API version.
    module Documents
      class Unknown < KeyError; end

      def self.fetch(name)
        cache.fetch(name.to_s) { raise Unknown, "no GraphQL document named #{name}" }
      end

      def self.names
        cache.keys
      end

      def self.cache
        @cache ||= Dir[DOCUMENTS_DIR.join('*.graphql').to_s].sort.to_h do |file|
          [File.basename(file, '.graphql'), File.read(file).freeze]
        end.freeze
      end
      private_class_method :cache
    end
  end
end
