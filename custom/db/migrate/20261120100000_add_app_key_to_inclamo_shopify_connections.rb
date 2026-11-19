# frozen_string_literal: true

# A store connection made through the store app (capability app-store-access):
# why such a connection is broken when the app's answer says why
# (`app_removed`, `account_mismatch`, `missing_read_scope`), and when the app
# last handed out a key for it. The new kind `app_key` needs no column: the
# kind is a string.
class AddAppKeyToInclamoShopifyConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :inclamo_shopify_connections, :broken_reason, :string, null: true
    add_column :inclamo_shopify_connections, :renewed_at, :datetime, null: true
  end
end
