# frozen_string_literal: true

module Inclamo
  module Ai
    # The AI agent's protected reply (ai-reply-ownership, design D2): the
    # conversation row is locked, its status read and the reply saved in one
    # transaction. A person's take-over writes the same row inside its own
    # transaction (Custom::Concerns::Message, Custom::Concerns::Conversation,
    # Chatwoot's assignment service), so it falls either before the check and
    # the reply is refused, or after the reply. Nothing slow runs under the
    # lock: the reply is text, and delivery, events and webhooks run after
    # commit. Liquid in the text (`{{order.number}}` reads the store) is
    # rendered before the lock is taken. The message is built by Chatwoot's own
    # builder as the bot, so it is the same message a reply through
    # POST …/messages makes.
    class ProtectedReply
      # The conversation's status as read under the lock.
      attr_reader :status

      def initialize(conversation:, bot:, content:)
        @conversation_id = conversation.id
        @bot = bot
        @content = content
      end

      # The new message, or nil when the conversation is no longer Pending.
      def perform
        content = rendered(@content)
        Conversation.transaction do
          # A fresh copy of the row, locked; the caller's object is not touched.
          conversation = Conversation.lock.find(@conversation_id)
          @status = conversation.status
          conversation.pending? ? build(conversation, content) : nil
        end
      end

      private

      def build(conversation, content)
        Messages::MessageBuilder.new(@bot, conversation, { content: content, message_type: 'outgoing' }.with_indifferent_access).perform
      end

      # Chatwoot renders Liquid in an outgoing message before it is created
      # (Liquidable); doing it here keeps a store read out of the lock. The
      # rendered text has no tags left, so the builder's second pass is a no-op.
      def rendered(content)
        return content unless content.include?('{{')

        conversation = Conversation.find(@conversation_id)
        draft = Message.new(conversation: conversation, account: conversation.account, inbox: conversation.inbox, sender: @bot,
                            message_type: :outgoing, content: content)
        draft.send(:process_liquid_in_content)
        draft.content
      end
    end
  end
end
