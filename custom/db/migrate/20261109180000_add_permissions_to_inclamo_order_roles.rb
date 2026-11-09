# frozen_string_literal: true

class AddPermissionsToInclamoOrderRoles < ActiveRecord::Migration[7.1]
  def change
    # A pre-existing row meant every non-discount operation. The default also
    # preserves the legacy administrator-only bulk grant API. A granular grant
    # always starts with an explicit empty array.
    add_column :inclamo_order_roles, :permissions, :jsonb, null: false,
               default: %w[cancel refund address replacement order_tags order_note customer_tags customer_note new_order edit_items]
  end
end
