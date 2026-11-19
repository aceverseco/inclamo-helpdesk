# frozen_string_literal: true

module Inclamo
  module Erasure
    # Deletes one shopper's data from a store's account: what an
    # administrator's "Delete" does, and what the daily run does when nobody
    # deleted or held in time (docs/app-store-erasure.md §4.2).
    #
    # The shopper is looked for again at this moment (Shoppers), so a
    # conversation the shopper started after the ticket was made goes too.
    # Each contact found is destroyed whole with Chatwoot's own model: its
    # conversations, messages and their files, its contact inboxes and notes
    # go with it (part of that in background jobs, within minutes). Nothing is
    # blanked instead of deleted. A contact who is online is deleted all the
    # same: the dashboard's check for that is its own, not the model's.
    #
    # The overlay's rows about those contacts, their conversations and the
    # orders the request lists are deleted first (REACH), so that none of them
    # holds a conversation back or outlives it; the account's cached store
    # answers are forgotten.
    #
    # Answers the number of contacts deleted. The caller finishes the ticket
    # (ShopperFinish) in the same transaction.
    class ShopperDeletion
      # How the deletion reaches each table of the overlay that names a
      # contact, a conversation or an order (References::LIST, every column
      # but `account_id`). A table added there with such a column must be
      # given its place here; the spec of this list fails until it is.
      #   :deleted            its rows about the shopper are deleted here
      #   :with_conversation  its rows go with the conversation (a foreign key
      #                       ON DELETE CASCADE) and are never a shopper's own
      #   :not_a_shopper      its rows name the tickets' own contact
      #   :kept               the erasures' own record (References::KEPT)
      REACH = {
        'inclamo_ai_identity_verifications' => :deleted,
        'inclamo_ai_proposals' => :deleted,
        'inclamo_call_conversations' => :deleted,
        'inclamo_data_request_inboxes' => :not_a_shopper,
        'inclamo_erasure_requests' => :kept,
        'inclamo_order_actions' => :deleted,
        'inclamo_sla_timers' => :deleted,
        'inclamo_support_central_requests' => :with_conversation
      }.freeze

      ORDER_GID = 'gid://shopify/Order/%s'

      # Deletes what matches the request's email and phone now.
      def self.call(request)
        account = Account.find_by(id: request.account_id)
        return 0 unless account

        new(account, Shoppers.matching(account, email: request.email, phone: request.phone).to_a, request.order_ids).call
      end

      # `contacts` are contacts of `account`; `order_ids` Shopify's order ids.
      def initialize(account, contacts, order_ids)
        @account = account
        @contacts = contacts
        @order_ids = order_ids
      end

      def call
        ids = @contacts.map(&:id)
        conversations = Conversation.where(account_id: @account.id, contact_id: ids).pluck(:id)
        contact_inboxes = ContactInbox.where(contact_id: ids).pluck(:id)
        delete_rows(@account.id, ids, conversations, contact_inboxes)
        @contacts.each(&:destroy!)
        Shopify::OrderReader.forget!(@account.id)
        @contacts.size
      end

      private

      def delete_rows(account_id, contact_ids, conversation_ids, contact_inbox_ids)
        Inclamo::AiProposal.where(conversation_id: conversation_ids).delete_all
        Inclamo::AiIdentityVerification.where(contact_inbox_id: contact_inbox_ids).delete_all
        Inclamo::CallConversation.where(account_id: account_id)
                                 .where(contact_id: contact_ids).or(Inclamo::CallConversation.where(conversation_id: conversation_ids))
                                 .delete_all
        Inclamo::SlaTimer.where(conversation_id: conversation_ids).delete_all
        actions = Inclamo::OrderAction.where(account_id: account_id)
        actions.where(conversation_id: conversation_ids).or(actions.where(order_id: listed_orders)).delete_all
      end

      # Shopify's order ids as the request gave them, and as the overlay keeps
      # them (global ids).
      def listed_orders
        ids = Array(@order_ids).map(&:to_s).compact_blank
        ids + ids.map { |id| format(ORDER_GID, id) }
      end
    end
  end
end
