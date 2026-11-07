# frozen_string_literal: true

class AddCustomerIdToInclamoOrderActions < ActiveRecord::Migration[7.1]
  def change
    # A change of a customer's tags or note has a customer and no order.
    add_column :inclamo_order_actions, :customer_id, :string
    change_column_null :inclamo_order_actions, :order_id, true
    add_index :inclamo_order_actions, [:account_id, :customer_id]
  end
end
