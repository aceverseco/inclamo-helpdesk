# frozen_string_literal: true

module Inclamo
  module Shopify
    # The GraphQL documents we send, one operation per file in
    # custom/graphql/shopify. They are files so that CI can validate each one
    # against the published schema of the pinned API version. A document may
    # spread fragments from the fragments/ directory (one per file, named like
    # the fragment); they are appended to it here and in the schema check.
    module Documents
      class Unknown < KeyError; end

      SPREAD = /\.\.\.\s*([A-Z]\w*)/

      def self.fetch(name)
        cache.fetch(name.to_s) { raise Unknown, "no GraphQL document named #{name}" }
      end

      def self.names
        cache.keys
      end

      def self.cache
        @cache ||= Dir[DOCUMENTS_DIR.join('*.graphql').to_s].sort.to_h do |file|
          [File.basename(file, '.graphql'), with_fragments(File.read(file)).freeze]
        end.freeze
      end
      private_class_method :cache

      def self.with_fragments(source)
        needed = []
        queue = source.scan(SPREAD).flatten
        until queue.empty?
          name = queue.shift
          next if needed.include?(name)

          needed << name
          queue.concat(fragment(name).scan(SPREAD).flatten)
        end
        ([source.rstrip] + needed.map { |name| fragment(name).rstrip }).join("\n\n") + "\n"
      end
      private_class_method :with_fragments

      def self.fragment(name)
        File.read(DOCUMENTS_DIR.join('fragments', "#{name}.graphql"))
      rescue Errno::ENOENT
        raise Unknown, "no GraphQL fragment named #{name}"
      end
      private_class_method :fragment
    end
  end
end
