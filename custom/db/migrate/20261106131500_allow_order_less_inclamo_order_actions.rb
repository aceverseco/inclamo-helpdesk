# frozen_string_literal: true

class AllowOrderLessInclamoOrderActions < ActiveRecord::Migration[7.1]
  # A new order is not about an existing order: its record has no order id.
  def change
    change_column_null :inclamo_order_actions, :order_id, true
  end
end
