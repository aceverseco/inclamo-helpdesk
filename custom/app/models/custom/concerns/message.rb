# frozen_string_literal: true

# A person's public reply takes a Pending conversation of a connected inbox
# from the AI agent in the same transaction as the reply (ai-reply-ownership,
# design D3). The conversation row is locked before the reply is inserted:
# the agent's protected reply (Inclamo::Ai::ProtectedReply) takes the same
# lock, so it is saved wholly before the person's reply or refused, and never
# lands between the person's INSERT and the take-over. Chatwoot's own rule for
# this is a Captain hook that the Community Edition turns off and that runs
# after commit (app/models/message.rb:423-433). Inclamo::AiAgentListener stays
# the fallback for any path that skips these callbacks.
#
# Included through Chatwoot's extension hook,
# `Message.include_mod_with('Concerns::Message')` (app/models/message.rb:473).
module Custom::Concerns::Message
  extend ActiveSupport::Concern

  included do
    before_create :inclamo_take_over_for_person
    after_create_commit :inclamo_announce_take_over
  end

  private

  def inclamo_take_over_for_person
    return unless outgoing? && !private? && sender.is_a?(User)

    connection = Inclamo::AiConnection.active_for(account_id)
    return unless connection&.covers?(inbox_id)

    # A fresh copy of the row, locked only while it is still Pending (an Open
    # conversation, the common case, is not locked). The caller's object is not
    # used: it may carry unsaved attributes, and Rails refuses to lock it then.
    locked = Conversation.pending.lock.find_by(id: conversation_id)
    return unless locked

    locked.bot_handoff!(dispatch_event: false)
    @inclamo_took_over = locked
  rescue ActiveRecord::RecordInvalid => e
    # The person's reply must not fail on the conversation's own validations;
    # the listener hands the conversation over after commit instead (D4).
    Rails.logger.warn("[inclamo] take-over left to the listener for conversation #{conversation_id}: #{e.message}")
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
