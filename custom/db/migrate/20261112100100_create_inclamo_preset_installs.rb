# frozen_string_literal: true

# What the installer of ready material has already offered an account, so an
# item the store edited is never rewritten and one it deleted never comes
# back (capability ready-replies).
class CreateInclamoPresetInstalls < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_preset_installs do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :key, null: false
      # false: the store already had its own item in the place of the ready one.
      t.boolean :created, null: false, default: true
      t.datetime :installed_at, null: false
    end
    add_index :inclamo_preset_installs, [:account_id, :kind, :key], unique: true
  end
end
