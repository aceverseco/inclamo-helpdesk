# frozen_string_literal: true

class CreateInclamoOrderActions < ActiveRecord::Migration[7.1]
  def change
    # Every attempt to act on an order, accepted or not. Kept when the store
    # connection is removed. Holds no personal data: never an address.
    create_table :inclamo_order_actions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: true, foreign_key: { on_delete: :nullify }
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      # Made by the dialog when it opens; a repeated request carries the same one.
      t.string :action_id, null: false
      t.string :action, null: false
      t.string :order_id, null: false
      t.string :order_number
      t.jsonb :params, null: false, default: {}
      # pending, running, accepted, refused, unknown
      t.string :outcome, null: false, default: 'pending'
      t.string :refusal
      t.text :store_message
      # What the action has done so far, to continue or to settle it later.
      t.jsonb :progress, null: false, default: {}
      t.bigint :note_message_id
      t.datetime :completed_at
      t.timestamps
    end
    add_index :inclamo_order_actions, [:account_id, :action_id], unique: true
    add_index :inclamo_order_actions, [:account_id, :order_id]
  end
end
