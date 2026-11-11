# frozen_string_literal: true

class CreateInclamoWebsiteWidgets < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_website_widgets do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
  end
end
