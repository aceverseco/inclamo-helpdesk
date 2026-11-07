# frozen_string_literal: true

class CreateInclamoDiscountPresets < ActiveRecord::Migration[7.1]
  # The discounts an administrator allows agents to give, set once: an agent
  # picks one and changes nothing. A code keeps its own conditions in its
  # action record, so changing or removing a preset changes no code.
  def change
    create_table :inclamo_discount_presets do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :kind, null: false
      t.decimal :value, precision: 12, scale: 2, null: false
      t.integer :expires_in_days
      t.integer :usage_limit, null: false, default: 1
      t.string :audience, null: false
      t.timestamps
    end
  end
end
