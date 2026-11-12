# frozen_string_literal: true

class CreateInclamoSupportNotificationPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_support_notification_preferences do |t|
      t.references :account_user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true, name: 'inclamo_support_notification_member' }
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
  end
end
