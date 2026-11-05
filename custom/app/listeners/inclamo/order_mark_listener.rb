# frozen_string_literal: true

# When a customer's first message arrives, looks for an order number in it.
class Inclamo::OrderMarkListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming?
    return unless message.conversation.messages.incoming.count == 1
    return unless Inclamo::ShopifyConnection.working.exists?(account_id: account.id)

    Inclamo::AutoMarkOrderJob.perform_later(message.conversation_id, message.id)
  end
end
