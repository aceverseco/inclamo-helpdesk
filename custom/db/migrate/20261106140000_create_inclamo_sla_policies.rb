# frozen_string_literal: true

class CreateInclamoSlaPolicies < ActiveRecord::Migration[7.1]
  def change
    # Response and resolution targets of an account. The first policy in the
    # list (by position) that covers a conversation's inbox applies to it.
    # Chatwoot's own sla_policies table belongs to its paid edition and is not used.
    create_table :inclamo_sla_policies do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      # Targets in seconds; at least one of the two is set.
      t.integer :first_response_seconds
      t.integer :resolution_seconds
      t.boolean :business_hours_only, null: false, default: false
      t.boolean :all_inboxes, null: false, default: true
      t.bigint :inbox_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :inclamo_sla_policies, [:account_id, :position]
  end
end
