# frozen_string_literal: true

module Inclamo
  module Shopify
    # Writes the overlay's attributes on a conversation without losing anyone
    # else's: events of one conversation are worked on in parallel, so the row
    # is locked and read again before it is changed.
    module ConversationAttributes
      # Replaces `keys` with `values` and leaves every other attribute alone;
      # nothing is written when nothing changed. A quiet write announces
      # nothing: Chatwoot publishes no "conversation updated" event for it, so
      # no automation rule is evaluated because of it. Returns the attributes.
      def self.replace!(conversation, keys, values, quiet: false)
        Conversation.transaction do
          stored = Conversation.lock.find(conversation.id)
          current = stored.custom_attributes.to_h
          updated = current.except(*keys).merge(values)
          if updated != current
            # rubocop:disable Rails/SkipsModelValidations
            quiet ? stored.update_columns(custom_attributes: updated) : stored.update!(custom_attributes: updated)
            # rubocop:enable Rails/SkipsModelValidations
          end
          # The caller's copy follows, so a later write through it undoes nothing.
          conversation.custom_attributes = updated
          conversation.clear_attribute_changes(%w[custom_attributes])
          updated
        end
      end
    end
  end
end
