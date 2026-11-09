# frozen_string_literal: true

class AddMacroIdToInclamoOrderActions < ActiveRecord::Migration[7.1]
  def change
    # The macro an order step ran in; empty for an action from the panel.
    # No foreign key: the record stays complete when the macro is deleted.
    add_column :inclamo_order_actions, :macro_id, :bigint
  end
end
