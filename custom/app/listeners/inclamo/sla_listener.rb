# frozen_string_literal: true

# SLA timers on Chatwoot's events (design D2): a new conversation gets the
# first covering policy, the first human reply and the first resolution reach
# the two targets. A failure here is reported and never fails the event for
# Chatwoot's own listeners.
class Inclamo::SlaListener < BaseListener
  def conversation_created(event)
    conversation, = extract_conversation_and_account(event)
    safely(conversation.account) { Inclamo::Sla::Timers.apply!(conversation) }
  end

  def message_created(event)
    message, account = extract_message_and_account(event)
    safely(account) { Inclamo::Sla::Timers.replied!(message) }
  end

  def conversation_resolved(event)
    conversation, = extract_conversation_and_account(event)
    safely(conversation.account) { Inclamo::Sla::Timers.resolved!(conversation, event.timestamp || Time.current) }
  end

  private

  def safely(account)
    yield
  rescue StandardError => e
    Rails.logger.error("[inclamo] SLA timer not updated: #{e.class.name}: #{e.message}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end
