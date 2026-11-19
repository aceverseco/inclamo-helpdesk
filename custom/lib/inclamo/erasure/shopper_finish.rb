# frozen_string_literal: true

module Inclamo
  module Erasure
    # Finishes the ticket of a request about one shopper: deleted (by an
    # administrator or automatically), or a data request marked answered
    # (docs/app-store-erasure.md §4.2, §5). Afterwards neither the request nor
    # its ticket holds the shopper's email or phone in readable form:
    # - the request keeps only the digests; its readable email and phone and a
    #   hold's reason are emptied, and it says when it was done and by whom;
    # - every message of the ticket that holds the email (in any letter case)
    #   or the phone's digits (with any spaces, dashes, dots or brackets
    #   between them) has them replaced with a fixed placeholder: a colleague
    #   may have written them into a note. A name or an address typed by hand
    #   is not found, which the ticket's first note says;
    # - a last note says it is done, when, and by which administrator or that
    #   the helpdesk did it; the ticket is resolved.
    # A completed erasure is journaled (Journal) before the caller's
    # transaction commits; a journal that cannot be written raises
    # Journal::Unwritable, and nothing of the deletion is kept.
    class ShopperFinish
      # `by` is the administrator, nil when the helpdesk does it by itself.
      # The re-application after a restore (Reapply) finishes a ticket the
      # restore brought back as it was finished before: with the journal's
      # `done_by` and time, and without a second journal line.
      def initialize(request, by: nil, now: Time.current, done_by: nil, journal: true)
        @request = request
        @by = by
        @now = now
        @done_by = done_by || (by ? 'team' : 'automatic')
        @journal = journal
      end

      def call
        conversation = Ticket.conversation_of(@request)
        patterns = patterns(@request.email, @request.phone)
        @request.update!(state: 'done', done_by: @done_by, done_by_id: @by&.id, completed_at: @now,
                         email: nil, phone: nil, hold_reason: nil)
        if conversation
          clean(conversation, patterns)
          Ticket.note!(conversation, last_note(conversation.account), author: @by)
          Ticket.resolve!(conversation)
        end
        Journal.append(Journal.shopper_entry(@request)) if @journal && @request.shopper_erasure?
        @request
      end

      def clean(conversation, patterns)
        return if patterns.empty?

        placeholder = Words.t(conversation.account, 'placeholder')
        Message.where(conversation_id: conversation.id).find_each do |message|
          cleaned = patterns.reduce(message.content.to_s) { |text, pattern| text.gsub(pattern, placeholder) }
          next if cleaned == message.content.to_s

          message.content = cleaned
          message.save!(validate: false)
        end
      end

      def patterns(email, phone)
        list = []
        list << Regexp.new(Regexp.escape(email.to_s.strip), Regexp::IGNORECASE) if email.to_s.strip.present?
        digits = Shoppers.digits(phone)
        list << Regexp.new("(?<!\\d)\\+?#{digits.chars.join('[\\s().\\-/]*')}(?!\\d)") if digits
        list
      end

      private

      def last_note(account)
        time = Words.time(@now)
        if @request.data_request?
          Words.t(account, 'notes.answered_by', name: @by&.available_name, time: time)
        elsif @done_by == 'team'
          Words.t(account, 'notes.deleted_by', name: @by&.available_name, time: time)
        else
          Words.t(account, 'notes.deleted_automatically', time: time)
        end
      end
    end
  end
end
