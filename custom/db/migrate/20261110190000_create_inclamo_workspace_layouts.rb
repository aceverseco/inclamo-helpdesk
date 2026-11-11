# frozen_string_literal: true

class CreateInclamoWorkspaceLayouts < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_workspace_defaults do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.jsonb :layout
      t.bigint :revision, null: false, default: 0
      t.timestamps
    end
    create_table :inclamo_workspace_preferences do |t|
      t.references :account_user, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.jsonb :layout
      t.bigint :revision, null: false, default: 0
      t.timestamps
    end
  end
end
