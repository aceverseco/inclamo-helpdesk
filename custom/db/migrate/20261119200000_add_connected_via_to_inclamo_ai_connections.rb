# frozen_string_literal: true

# Which door a connection to the AI agent came through (capability
# app-agent-auto-connection): `page`, an administrator with a connection code
# on the "AI agent" page, or `app`, the store app over the provisioning
# channel. Every connection made before this column was made on the page.
class AddConnectedViaToInclamoAiConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :inclamo_ai_connections, :connected_via, :string, null: false, default: 'page'
    add_check_constraint :inclamo_ai_connections, "connected_via IN ('page', 'app')", name: 'inclamo_ai_connections_connected_via'
  end
end
