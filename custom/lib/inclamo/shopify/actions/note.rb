# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Replaces the note of an order or of a customer. The text passes through
      # to the store and is not kept: a note may hold a phone number or an
      # address, so the record and the private note only say that it changed
      # (design D4). An empty text clears the note.
      class Note < Base
        RECORDED = [].freeze

        def self.context(connection:, extra:)
          { note: extra[:note].nil? ? extra['note'] : extra[:note] }
        end

        def resolve
          nil # The original note text is deliberately not persisted. Never write on a read.
        end

        def initialize(note:, **rest)
          super(**rest)
          @note = note.to_s
        end

        def call
          answer = if @record.customer_action?
                     @store.query(:customer_note_update, { input: { id: @record.customer_id, note: @note } })['customerUpdate']
                   else
                     @store.query(:order_note_update, { input: { id: @record.order_id, note: @note } })['orderUpdate']
                   end
          user_errors!(answer['userErrors'])
          :accepted
        end
      end
    end
  end
end
