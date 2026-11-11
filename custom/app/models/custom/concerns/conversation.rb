# frozen_string_literal: true

# Assigning a person to a Pending conversation of a connected inbox opens it
# in the same UPDATE (ai-reply-ownership, design D3). Chatwoot's assignment
# service already does this under the row lock when the AI agent is the
# conversation's AI assignee (app/services/conversations/assignment_service.rb:16-27);
# this covers what it leaves Pending: a conversation the shopper reopened
# after an earlier hand-over (no AI assignee) and assignments made outside
# that service. Runs before validation so that Chatwoot's `before_save`
# callbacks (status_changed_at) see the new status.
#
# Included through Chatwoot's extension hook,
# `Conversation.include_mod_with('Concerns::Conversation')` (app/models/conversation.rb:444).
module Custom::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    before_validation :inclamo_open_on_person_assignment, on: :update
  end

  private

  def inclamo_open_on_person_assignment
    return unless will_save_change_to_assignee_id? && assignee_id.present?
    return unless pending? && status_in_database == 'pending'

    connection = Inclamo::AiConnection.active_for(account_id)
    return unless connection&.covers?(inbox_id)

    self.status = :open
    self.waiting_since = Time.current if waiting_since.blank?
    self.ai_assignee = nil
  end
end
