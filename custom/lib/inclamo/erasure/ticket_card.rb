# frozen_string_literal: true

module Inclamo
  module Erasure
    # What the card of a ticket about one shopper shows its administrators
    # (Api::V1::Accounts::Inclamo::ShopperRequestsController): the kind and
    # state of the request, when it was received, the date of automatic
    # deletion, a hold with its author, time and reason, how it was done, and,
    # while it is not done, the shopper's email and phone as Shopify gave them
    # and the account's contacts that match them now with their conversations.
    # A done request shows neither: its readable values are gone.
    class TicketCard
      def initialize(request, now: Time.current)
        @request = request
        @now = now
      end

      def as_json(*)
        {
          id: @request.id, kind: @request.kind, state: @request.state, conversation_id: @request.conversation_id,
          received_at: time(@request.received_at), delete_after: time(@request.delete_after),
          overdue: Shoppers.overdue?(@request, @now),
          email: (@request.email unless @request.done?), phone: (@request.phone unless @request.done?),
          contacts: contacts, hold: hold, done: done
        }
      end

      private

      def contacts
        return [] if @request.done?

        account = Account.find_by(id: @request.account_id)
        found = Shoppers.matching(account, email: @request.email, phone: @request.phone).order(:id).to_a
        counts = Conversation.where(contact_id: found.map(&:id)).group(:contact_id).count
        found.map { |contact| { id: contact.id, name: contact.name, conversations: counts.fetch(contact.id, 0) } }
      end

      def hold
        return unless @request.held?

        { reason: @request.hold_reason, held_at: time(@request.held_at), held_by: person(@request.held_by_id) }
      end

      def done
        return unless @request.done?

        { at: time(@request.completed_at), by: @request.done_by, user: person(@request.done_by_id) }
      end

      def person(id)
        user = id && User.find_by(id: id)
        user ? { id: user.id, name: user.available_name } : nil
      end

      def time(value)
        value&.utc&.iso8601
      end
    end
  end
end
