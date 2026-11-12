# frozen_string_literal: true

# Team queues: one definition per account, shown to every staff member
# (capability team-queues). `query` is Chatwoot's own saved-filter payload.
class CreateInclamoTeamQueues < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_team_queues do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      # The ready queue's stable key; null is kept for queues a store defines itself.
      t.string :key
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :hidden, null: false, default: false
      t.jsonb :query, null: false, default: {}
      t.timestamps
    end
    add_index :inclamo_team_queues, [:account_id, :key], unique: true
    add_index :inclamo_team_queues, [:account_id, :position]
  end
end
