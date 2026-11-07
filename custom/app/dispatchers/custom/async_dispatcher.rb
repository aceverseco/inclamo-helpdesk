# frozen_string_literal: true

# Adds the overlay's listeners to Chatwoot's event dispatcher, through the
# extension hook Chatwoot calls at the end of AsyncDispatcher.
module Custom::AsyncDispatcher
  def listeners
    super + [Inclamo::OrderMarkListener.instance]
  end
end
