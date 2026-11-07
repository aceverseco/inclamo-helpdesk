# frozen_string_literal: true

class CreateInclamoAiConnections < ActiveRecord::Migration[7.1]
  def change
    # The account's link to the AI service. The agent bot's token and secret
    # stay in Chatwoot's own tables; nothing secret is stored here. A
    # disconnected row is kept for its history and reused by the next
    # connection.
    create_table :inclamo_ai_connections do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :service_url, null: false
      # The AI service's own id of this connection.
      t.string :connection_id
      t.bigint :agent_bot_id
      t.bigint :phone_inbox_id
      t.jsonb :inbox_ids, null: false, default: []
      # connected, failing, disconnected
      t.string :state, null: false, default: 'connected'
      t.datetime :last_delivered_at
      t.datetime :last_failed_at
      # The kind of the last failed delivery (an HTTP status or an error class), never a body.
      t.string :last_error
      t.datetime :last_reply_at
      t.references :connected_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :connected_at
      t.datetime :disconnected_at
      # Set when the AI service could not be told about a disconnection.
      t.string :removal_error
      t.timestamps
    end
  end
end
