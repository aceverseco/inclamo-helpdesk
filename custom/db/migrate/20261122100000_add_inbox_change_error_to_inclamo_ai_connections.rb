# frozen_string_literal: true

# Why the last change of the AI agent's inboxes was not completed (capability
# agent-inbox-selection): `not_applied` when the AI service accepted a list the
# helpdesk could not apply and took the earlier list back,
# `not_applied_service_not_told` when it could not be asked to take it back,
# and `storefront_not_added` when a storefront chat inbox made again could not
# be given to the agent. Empty otherwise: every connection made before this
# column, and every connection after a change that succeeded.
class AddInboxChangeErrorToInclamoAiConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :inclamo_ai_connections, :inbox_change_error, :string
  end
end
