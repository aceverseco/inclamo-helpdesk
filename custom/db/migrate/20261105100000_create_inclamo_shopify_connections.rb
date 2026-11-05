# frozen_string_literal: true

class CreateInclamoShopifyConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_shopify_connections do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :shop_domain, null: false
      t.string :shop_name
      t.string :shop_currency
      t.string :auth_kind, null: false
      t.string :client_id
      # Encrypted by the model (Active Record encryption); never plain text.
      t.text :client_secret
      t.text :access_token
      t.datetime :token_expires_at
      t.jsonb :scopes, null: false, default: []
      t.string :api_version, null: false
      t.string :customer_data_mode, null: false, default: 'full'
      t.string :status, null: false, default: 'working'
      t.datetime :last_checked_at
      t.timestamps
    end
  end
end
