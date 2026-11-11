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
    # commit. The message is built by Chatwoot's own builder as the bot, so it
    # is the same message a reply through POST …/messages makes.
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
        Conversation.transaction do
          # A fresh copy of the row, locked; the caller's object is not touched.
          conversation = Conversation.lock.find(@conversation_id)
          @status = conversation.status
          conversation.pending? ? build(conversation) : nil
        end
      end

      private

      def build(conversation)
        Messages::MessageBuilder.new(@bot, conversation, { content: @content, message_type: 'outgoing' }.with_indifferent_access).perform
      end
    end
  end
end
