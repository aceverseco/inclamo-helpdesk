# frozen_string_literal: true

class CreateInclamoAiAuthority < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_ai_policies do |t|
      t.references :account, null: false, foreign_key: true
      t.string :action, null: false
      t.string :mode, null: false, default: 'propose'
      t.jsonb :limits, null: false, default: {}
      t.timestamps
    end
    add_index :inclamo_ai_policies, [:account_id, :action], unique: true
    create_table :inclamo_ai_proposals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.bigint :agent_bot_id, null: false
      t.bigint :approved_by_id
      t.string :request_id, null: false
      t.string :request_digest, null: false
      t.string :review_digest, null: false
      t.string :action, null: false
      t.string :state, null: false, default: 'proposed'
      t.string :reason
      t.text :payload, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :inclamo_ai_proposals, [:account_id, :request_id], unique: true
    create_table :inclamo_ai_identity_verifications do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact_inbox, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :customer_id, null: false
      t.string :identity_digest, null: false
      t.timestamps
    end
    add_index :inclamo_ai_identity_verifications, [:account_id, :contact_inbox_id], unique: true, name: 'index_inclamo_ai_identity_scope'
    add_column :inclamo_order_actions, :ai_proposal_id, :bigint
    add_index :inclamo_order_actions, :ai_proposal_id
  end
end
