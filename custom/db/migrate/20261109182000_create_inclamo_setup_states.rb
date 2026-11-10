# frozen_string_literal: true

class CreateInclamoSetupStates < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_setup_states do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :reviews, null: false, default: {}
      t.datetime :completed_at
      t.timestamps
    end
  end
end
