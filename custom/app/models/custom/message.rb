# frozen_string_literal: true

# Adds the order of the conversation to what an outgoing message can name:
# `{{order.number}}` and the other order variables. Prepended to Message
# through the extension hook Chatwoot calls at the end of the model.
module Custom::Message
  private

  def message_drops
    super.merge('order' => Inclamo::OrderDrop.new(conversation))
  end
end
