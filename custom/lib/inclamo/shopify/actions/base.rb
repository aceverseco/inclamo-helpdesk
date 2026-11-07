# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # The store said no: nothing was changed.
      class Refused < StandardError
        attr_reader :code

        def initialize(code, message = nil)
          super(message || code)
          @code = code
        end
      end

      # One order action. `call` returns :accepted or :running, raises Refused
      # when the store or the order does not allow it, and lets errors of the
      # store connection through. It must be safe to call again with the same
      # record: that is how a repeated request continues an attempt whose
      # answer was lost.
      class Base
        def initialize(store:, record:, order:)
          @store = store
          @record = record
          @order = order
        end

        # The parameters as they may be kept in the action record: no personal data.
        def self.recordable(params)
          params.to_h.slice(*self::RECORDED).transform_values { |value| value.is_a?(String) ? value.first(200) : value }
        end

        # What the handler is given besides the store, the record and the
        # order: from the connection, and from what the request brought and
        # must not be recorded (`extra`; empty when an open attempt is read).
        def self.context(connection:, extra:) # rubocop:disable Lint/UnusedMethodArgument
          {}
        end

        # Facts of the record for the private note, beside the ones every action has.
        def self.note_facts(_record)
          {}
        end

        # Where an open attempt stands, found by reading the store: :accepted,
        # :running, nil when the store does not tell, or Refused. Used when the
        # panel is read, so an action whose `call` would ask the store to act
        # again overrides it to read only.
        def resolve
          call
        end

        private

        def params
          @record.params
        end

        def user_errors!(errors)
          errors = Array(errors)
          return if errors.empty?

          raise Refused.new('store_refused', errors.map { |error| error['message'] }.join('; ').first(500))
        end

        def remember!(facts)
          @record.update!(progress: @record.progress.merge(facts.stringify_keys))
        end

        # A step on a draft the action made and will not finish without it.
        # When the store surely did not do the step (it said no, throttled,
        # refused the token or was not reached), the draft is removed and the
        # action refused. When the store may have done it, the error goes on:
        # the attempt is then unknown and the draft stays.
        def removing_draft_on_failure(draft_id, draft_name, shop_domain)
          yield
        rescue Refused => e
          raise Refused.new(e.code, [e.message, remove_draft(draft_id, draft_name, shop_domain)].compact.join(' '))
        rescue Error => e
          raise if e.outcome_unknown?

          refused = e.is_a?(Error::QueryError)
          raise Refused.new(refused ? 'store_refused' : 'store_unreachable',
                            [refused ? e.message.first(500) : e.class.name.demodulize.underscore,
                             remove_draft(draft_id, draft_name, shop_domain)].compact.join(' '))
        end

        # Removes the draft; when that fails, the words that name it with a
        # link, so that it is not left at the store unnoticed. Nil when removed.
        def remove_draft(draft_id, draft_name, shop_domain)
          answer = @store.query(:replacement_draft_delete, { id: draft_id })['draftOrderDelete']
          if Array(answer['userErrors']).empty?
            remember!(draft_removed: true)
            return
          end

          left_behind(draft_name, draft_id, shop_domain)
        rescue Error
          left_behind(draft_name, draft_id, shop_domain)
        end

        def left_behind(draft_name, draft_id, shop_domain)
          "The unfinished draft #{draft_name} could not be removed: #{Shopify.admin_url(shop_domain, 'draft_orders', draft_id)}"
        end
      end
    end
  end
end
