# frozen_string_literal: true

class CreateInclamoOrderRoles < ActiveRecord::Migration[7.1]
  def change
    # One row means: this member of the account may perform order actions.
    # Tied to the membership, so a removed agent loses the role with it.
    create_table :inclamo_order_roles do |t|
      t.references :account_user, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :granted_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
  end
end
