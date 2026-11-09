# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Adds or removes one tag of an order or of a customer. Only that tag
      # changes: the store keeps every other tag, also one added in the store
      # since the panel read it (design D1).
      class Tags < Base
        RECORDED = %w[operation tag].freeze
        OPERATIONS = { 'add' => [:tags_add, 'tagsAdd'], 'remove' => [:tags_remove, 'tagsRemove'] }.freeze

        # The tag is what the private note names, so it is kept; a tag is not
        # personal data the way a note may be. Kept long enough for the store
        # to judge it: the store, not we, refuses a tag that is too long.
        def self.recordable(params)
          { 'operation' => params['operation'].to_s.first(10), 'tag' => params['tag'].to_s.strip.first(1000) }
        end

        def call
          document, field = OPERATIONS.fetch(params['operation']) { raise Refused, 'unknown_operation' }
          tag = params['tag'].to_s
          # The store accepts an empty tag and changes nothing; a comma would
          # make it two tags.
          raise Refused, 'tag_missing' if tag.blank?
          raise Refused, 'tag_has_comma' if tag.include?(',')

          answer = @store.query(document, { id: subject_id, tags: [tag] })[field]
          user_errors!(answer['userErrors'])
          :accepted
        end

        private

        def subject_id
          @record.customer_action? ? @record.customer_id : @record.order_id
        end
      end
    end
  end
end
