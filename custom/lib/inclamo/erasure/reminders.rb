# frozen_string_literal: true

module Inclamo
  module Erasure
    # Reminders in a ticket about one shopper, written by the daily run as a
    # private note with fixed text; a resolved ticket is opened again by its
    # reminder. A private note of Chatwoot notifies only the people it
    # mentions, so each reminder mentions the account's administrators of that
    # moment (Ticket.addressed): each gets Chatwoot's notification of a
    # mention, and an administrator added or removed since the ticket was made
    # is counted as the account has them now.
    #
    # When a reminder is due:
    # - a waiting erasure: 7 days and 1 day before its automatic deletion,
    #   each only when it falls after the ticket was made;
    # - a held erasure: every 30 days from the hold;
    # - a waiting data request: on days 7, 14, 21 and 27 after it was received.
    # The request keeps when it was last reminded (`reminded_at`), and a run
    # writes one reminder for the latest moment that has come and is later
    # than that: each reminder is written once, and a run after missed days
    # writes one, not one for each.
    module Reminders
      BEFORE_DELETION = [7.days, 1.day].freeze
      HELD_EVERY = 30.days
      DATA_REQUEST_DAYS = [7, 14, 21, 27].freeze

      module_function

      # The moments a request is reminded at, up to `now`.
      def moments(request, now)
        if request.shopper_erasure? && request.waiting? && request.delete_after
          BEFORE_DELETION.map { |before| request.delete_after - before }.select { |moment| moment > request.received_at }
        elsif request.shopper_erasure? && request.held? && request.held_at
          (1..((now - request.held_at) / HELD_EVERY.to_i).floor).map { |times| request.held_at + (HELD_EVERY * times) }
        elsif request.data_request? && request.waiting?
          DATA_REQUEST_DAYS.map { |day| request.received_at + day.days }
        else
          []
        end
      end

      # The moment a reminder is due for, if one is.
      def due(request, now)
        moment = moments(request, now).select { |one| one <= now }.max
        moment if moment && (request.reminded_at.nil? || request.reminded_at < moment)
      end

      # Writes the request's due reminder, under its row's lock. Answers
      # whether it wrote one.
      def remind!(request, now: Time.current)
        Ticket.acting(request) do
          request.with_lock do
            next false unless due(request, now)

            conversation = Ticket.conversation_of(request)
            if conversation
              Ticket.note!(conversation, Ticket.addressed(conversation.account, text(request, conversation.account)))
              Ticket.reopen!(conversation)
            end
            request.update!(reminded_at: now)
            true
          end
        end
      end

      def text(request, account)
        if request.data_request?
          Words.t(account, 'notes.reminder_data_request', date: Words.time(request.received_at))
        elsif request.held?
          Words.t(account, 'notes.reminder_held', date: Words.time(request.held_at))
        else
          Words.t(account, 'notes.reminder_erasure', date: Words.time(request.delete_after))
        end
      end
    end
  end
end
