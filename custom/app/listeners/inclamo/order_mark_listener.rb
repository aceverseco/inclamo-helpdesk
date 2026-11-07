# frozen_string_literal: true

# When a customer's first message arrives, looks for an order number in it.
# The listener runs in a job, when later messages may have arrived already:
# "first" is decided by the messages that came before this one.
class Inclamo::OrderMarkListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming?
    return if message.conversation.messages.incoming.where(id: ...message.id).exists?
    return unless Inclamo::ShopifyConnection.working.exists?(account_id: account.id)

    Inclamo::AutoMarkOrderJob.perform_later(message.conversation_id, message.id)
  end
end
