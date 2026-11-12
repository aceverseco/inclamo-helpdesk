# frozen_string_literal: true

class CreateInclamoCallConversations < ActiveRecord::Migration[7.1]
  def change
    # The key of a filed call: one row per call id in an account, written in
    # the same transaction as the call's conversation. A repeat of the call
    # reads the row instead of filing again. Nothing of the call's content is
    # kept here.
    create_table :inclamo_call_conversations do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :call_id, null: false
      t.references :conversation, null: true, foreign_key: { on_delete: :cascade }
      t.bigint :contact_id
      # phone, email, created, anonymous, ambiguous
      t.string :matched_by
      t.datetime :created_at, null: false
    end
    add_index :inclamo_call_conversations, [:account_id, :call_id], unique: true
  end
end
