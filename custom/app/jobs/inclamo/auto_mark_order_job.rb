# frozen_string_literal: true

class Inclamo::AutoMarkOrderJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)
    return unless conversation && message

    Inclamo::Shopify::ConversationOrder.new(conversation).auto_mark!(message.content.to_s)
  rescue Inclamo::Shopify::Error => e
    # The agent can still mark the order by hand; nothing is retried.
    Rails.logger.info("[inclamo] order not marked automatically for conversation #{conversation_id}: #{e.class.name}")
  end
end
