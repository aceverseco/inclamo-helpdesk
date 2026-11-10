# frozen_string_literal: true

# What the helpdesk does around the AI agent's conversations (design D5, D8):
# - a person's public reply, or a person becoming the assignee, opens a pending
#   conversation of a connected inbox with Chatwoot's own handover, so the
#   agent gets `conversation_status_changed` and stops. Chatwoot's Community
#   Edition does not do this itself (app/models/message.rb:423-433);
# - a reply of the connection's bot is the time the agent last answered.
# A private note changes nothing. Runs in a job (Custom::AsyncDispatcher), so
# the conversation is read again before it is changed.
class Inclamo::AiAgentListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.outgoing?

    connection = Inclamo::AiConnection.active_for(account.id)
    return unless connection&.covers?(message.inbox_id)

    if connection.agent_bot?(message.sender)
      Inclamo::AiConnection.record_reply(connection.id, at: message.created_at)
    elsif message.sender.is_a?(User) && !message.private?
      hand_over(message.conversation_id)
    end
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    connection = Inclamo::AiConnection.active_for(account.id)
    return unless connection&.covers?(conversation.inbox_id)

    hand_over(conversation.id, assigned: true)
  end

  private

  def hand_over(conversation_id, assigned: false)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation&.pending?
    return if assigned && conversation.assignee_id.blank?

    conversation.bot_handoff!
  end
end
