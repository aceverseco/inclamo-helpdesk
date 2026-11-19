# frozen_string_literal: true

module Inclamo
  module Ai
    # Which inboxes may be the agent's: one rule for connecting
    # (Inclamo::Ai::Connect) and for changing the inboxes of a connection
    # (Inclamo::Ai::ChangeInboxes). Every chosen id must be an inbox of the
    # account, none the Phone inbox, and none may have another bot or a
    # Dialogflow integration (Chatwoot allows one bot provider per inbox,
    # app/models/concerns/inbox_bot_status.rb).
    module InboxChoice
      module_function

      # The chosen inboxes in the order they were given, or the error of the
      # first rule broken. `allow_empty` lets an empty choice through (a
      # connection for calls only); `own_bot_id` names the agent's own bot,
      # which an inbox may carry without counting as "another bot".
      def inboxes!(account, chosen, phone_inbox_id:, allow_empty: false, own_bot_id: nil)
        ids = Array(chosen).map(&:to_i).select(&:positive?).uniq
        return [] if ids.empty? && allow_empty
        raise Error::NoInboxes, 'no inbox was chosen' if ids.empty?

        inboxes = account.inboxes.where(id: ids).to_a
        raise Error::InvalidInbox, 'not an inbox of the account' if inboxes.size != ids.size
        raise Error::InvalidInbox, 'the Phone inbox takes no turns of the agent' if phone_inbox_id && ids.include?(phone_inbox_id)
        raise Error::InboxHasBot, 'an inbox has another bot' if inboxes.any? { |inbox| other_provider(inbox, own_bot_id) }

        inboxes.sort_by { |inbox| ids.index(inbox.id) }
      end

      # 'Agent Bot' or 'Dialogflow' when the inbox has a bot other than
      # `own_bot_id`, or nil. Chatwoot's own check counts every agent bot, so
      # an inbox whose only active bot is ours is asked about Dialogflow only.
      def other_provider(inbox, own_bot_id = nil)
        ours = own_bot_id.present? && AgentBotInbox.active.where(inbox_id: inbox.id).distinct.pluck(:agent_bot_id) == [own_bot_id]
        inbox.conflicting_bot_provider(ours ? :agent_bot : :inclamo)
      end
    end
  end
end
