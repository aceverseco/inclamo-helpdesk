# frozen_string_literal: true

# Assigning a person to a Pending conversation of a connected inbox opens it
# in the same save (ai-reply-ownership, design D3). Chatwoot's assignment
# service already does this under the row lock when the AI agent is the
# conversation's AI assignee (app/services/conversations/assignment_service.rb:16-27);
# this covers what it leaves Pending: a conversation the shopper reopened after
# an earlier hand-over (no AI assignee), a team's auto-assignment
# (AssignmentHandler#ensure_assignee_is_from_team, a before_save), a
# conversation created with a person assigned, and assignments made outside
# that service, with or without validation.
#
# Included through Chatwoot's extension hook,
# `Conversation.include_mod_with('Concerns::Conversation')` (app/models/conversation.rb:444).
module Custom::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    # Appended after Chatwoot's own callbacks: on an update after the team's
    # auto-assignment, on a create after determine_conversation_status.
    before_save :inclamo_open_on_person_assignment, unless: :new_record?
    before_create :inclamo_open_on_person_assignment
    after_commit :inclamo_announce_hand_over, on: [:create, :update]
  end

  private

  def inclamo_open_on_person_assignment
    return unless will_save_change_to_assignee_id? && assignee_id.present? && pending?

    connection = Inclamo::AiConnection.active_for(account_id)
    return unless connection&.covers?(inbox_id)
    # The status as stored, read under the row lock: a caller that loaded the
    # conversation earlier (a bulk action) must not reopen one resolved since.
    return unless new_record? || Conversation.lock.where(id: id).pick(:status) == 'pending'

    self.status = :open
    # Chatwoot's set_status_changed_at ran before this callback.
    self.status_changed_at = Time.current
    self.waiting_since = Time.current if waiting_since.blank?
    # Chatwoot clears it before validation; a save without validation does not.
    self.ai_assignee = nil
    @inclamo_handed_over = true
  end

  # The hand-over event the listener used to send for these assignments
  # (reports, notifications, the dashboard's live update).
  def inclamo_announce_hand_over
    return unless @inclamo_handed_over

    @inclamo_handed_over = false
    dispatch_bot_handoff_event
  end
end
