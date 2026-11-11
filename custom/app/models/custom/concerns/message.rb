# frozen_string_literal: true

# A person's public reply takes a Pending conversation of a connected inbox
# from the AI agent in the same transaction as the reply (ai-reply-ownership,
# design D3). The agent's protected reply locks the same conversation row
# (Inclamo::Ai::ProtectedReply), so it lands either before the person's reply
# or not at all. Chatwoot's own rule for this is a Captain hook that the
# Community Edition turns off and that runs after commit
# (app/models/message.rb:423-433). Inclamo::AiAgentListener stays as the
# fallback for any path that skips these callbacks.
#
# Included through Chatwoot's extension hook,
# `Message.include_mod_with('Concerns::Message')` (app/models/message.rb:473).
module Custom::Concerns::Message
  extend ActiveSupport::Concern

  included do
    after_create :inclamo_take_over_for_person
    after_create_commit :inclamo_announce_take_over
  end

  private

  def inclamo_take_over_for_person
    return unless outgoing? && !private? && sender.is_a?(User)

    connection = Inclamo::AiConnection.active_for(account_id)
    return unless connection&.covers?(inbox_id)

    # A fresh copy of the row, locked: the caller's conversation object may
    # carry unsaved attributes (Rails refuses to lock it then, and the person's
    # reply must not fail).
    locked = Conversation.lock.find(conversation_id)
    return unless locked.pending?

    # Without the event, bot_handoff! answers nil even when it opened the
    # conversation (app/models/conversation.rb:184-193).
    locked.bot_handoff!(dispatch_event: false)
    @inclamo_took_over = locked
  end

  # Chatwoot's hand-over event goes out once the take-over is committed, so no
  # listener reads the conversation before it is Open.
  def inclamo_announce_take_over
    taken = @inclamo_took_over
    return unless taken

    @inclamo_took_over = nil
    taken.dispatch_bot_handoff_event
  end
end
