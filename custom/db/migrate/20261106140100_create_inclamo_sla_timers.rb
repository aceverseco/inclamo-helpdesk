# frozen_string_literal: true

class CreateInclamoSlaTimers < ActiveRecord::Migration[7.1]
  def change
    # The policy applied to one conversation. The targets are copied when the
    # policy is applied, so a later edit of the policy does not move them.
    create_table :inclamo_sla_timers do |t|
      t.references :conversation, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      # Null once the policy is deleted; its name stays for the sidebar.
      t.references :policy, null: true, foreign_key: { to_table: :inclamo_sla_policies, on_delete: :nullify }
      t.string :policy_name, null: false
      t.integer :first_response_seconds
      t.integer :resolution_seconds
      t.boolean :business_hours_only, null: false, default: false
      t.datetime :started_at, null: false
      # The first public reply by a person, and the first resolution.
      t.datetime :first_response_at
      t.datetime :resolved_at
      # The moment each target passed; set once, by the periodic check or when a late reply or resolution arrives.
      t.datetime :first_response_missed_at
      t.datetime :resolution_missed_at
      # Set when the policy is deleted while the conversation is still open.
      t.datetime :stopped_at
      t.timestamps
    end
    add_index :inclamo_sla_timers, [:policy_id, :started_at]
    # The periodic check reads only timers with a target still running.
    add_index :inclamo_sla_timers, :started_at, name: 'index_inclamo_sla_timers_first_response_running',
                                                where: 'stopped_at IS NULL AND first_response_seconds IS NOT NULL ' \
                                                       'AND first_response_at IS NULL AND first_response_missed_at IS NULL'
    add_index :inclamo_sla_timers, :started_at, name: 'index_inclamo_sla_timers_resolution_running',
                                                where: 'stopped_at IS NULL AND resolution_seconds IS NOT NULL ' \
                                                       'AND resolved_at IS NULL AND resolution_missed_at IS NULL'
  end
end
