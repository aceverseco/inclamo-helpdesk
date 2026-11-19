# frozen_string_literal: true

module Inclamo
  module Erasure
    # What happens to a ticket about one shopper (docs/app-store-erasure.md
    # §4.2, §5): an administrator deletes the shopper's data, holds the
    # automatic deletion with a reason, lifts the hold, or marks a data request
    # answered; the daily run deletes when nobody deleted or held in time.
    # Each runs under the request's row lock, in the state it belongs to, and
    # writes a private note with fixed text, with the administrator as author.
    # Who may act is the caller's check (an administrator of the account).
    #
    # A hold stops the automatic deletion until it is lifted; from then on the
    # store answers for the request. Lifting does not start the days again:
    # the data is deleted on the original date, or at the next daily run when
    # that date has passed.
    module ShopperActions
      class WrongState < StandardError
        attr_reader :state

        def initialize(state)
          @state = state
          super("not allowed while the request is #{state}")
        end
      end

      class ReasonMissing < StandardError; end

      MAX_REASON = 1000

      module_function

      def delete!(request, user, now: Time.current)
        act(request, :shopper_erasure?, %w[waiting held], 'shopper_deleted') do
          ShopperDeletion.call(request)
          ShopperFinish.new(request, by: user, now: now).call
        end
      end

      # The daily run's deletion of a waiting request whose date has passed.
      # Answers whether it deleted: a request done, held or lifted to a later
      # date since it was chosen is left alone.
      def delete_automatically!(request, now: Time.current)
        deleted = Ticket.acting(request) do
          request.with_lock do
            next false unless request.shopper_erasure? && request.waiting? && request.delete_after && request.delete_after <= now

            ShopperDeletion.call(request)
            ShopperFinish.new(request, now: now).call
            true
          end
        end
        record('shopper_deleted', request) if deleted
        deleted
      end

      def hold!(request, user, reason, now: Time.current)
        reason = reason.to_s.strip
        act(request, :shopper_erasure?, %w[waiting], 'shopper_held') do
          raise ReasonMissing if reason.empty?

          request.update!(state: 'held', hold_reason: reason.first(MAX_REASON), held_by_id: user.id, held_at: now)
          ticket(request) do |conversation|
            Ticket.note!(conversation, Words.t(conversation.account, 'notes.held_by', name: user.available_name), author: user)
            Ticket.resolve!(conversation)
          end
        end
      end

      def lift!(request, user, now: Time.current)
        act(request, :shopper_erasure?, %w[held], 'shopper_hold_lifted') do
          request.update!(state: 'waiting', hold_reason: nil, held_by_id: nil, held_at: nil)
          ticket(request) do |conversation|
            Ticket.note!(conversation, lifted_note(request, conversation.account, user, now), author: user)
            Ticket.reopen!(conversation)
          end
        end
      end

      def answered!(request, user, now: Time.current)
        act(request, :data_request?, %w[waiting], 'data_request_answered') do
          ShopperFinish.new(request, by: user, now: now).call
        end
      end

      def act(request, kind, states, outcome)
        Ticket.acting(request) do
          request.with_lock do
            raise WrongState, request.state unless request.public_send(kind) && states.include?(request.state)

            yield
          end
        end
        record(outcome, request)
        request
      end

      def ticket(request)
        conversation = Ticket.conversation_of(request)
        yield conversation if conversation
      end

      def lifted_note(request, account, user, now)
        if request.delete_after && request.delete_after > now
          Words.t(account, 'notes.lifted_before', name: user.available_name, date: Words.time(request.delete_after))
        else
          Words.t(account, 'notes.lifted_after', name: user.available_name)
        end
      end

      def record(outcome, request)
        Inclamo::ProvisioningEvent.record(outcome: outcome, shop_domain: request.shop_domain, request_id: nil)
      end
    end
  end
end
