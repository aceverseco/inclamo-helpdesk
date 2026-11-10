# frozen_string_literal: true

# Prepended to Chatwoot's AutomationRuleListener (see custom/config/overlay.rb):
# before the rules of a new conversation and of the customer's first message
# are evaluated, the store's facts about the customer are written and the order
# the customer names is tied. Chatwoot's own method then runs unchanged,
# whatever happened here.
module Inclamo::StoreFactsBeforeRules
  def conversation_created(event)
    Inclamo::Shopify::BeforeRules.call(event.data[:conversation])
    super
  end

  def message_created(event)
    message = event.data[:message]
    Inclamo::Shopify::BeforeRules.call(message.conversation, message: message) if Inclamo::Shopify::BeforeRules.first_from_customer?(message)
    super
  end
end
