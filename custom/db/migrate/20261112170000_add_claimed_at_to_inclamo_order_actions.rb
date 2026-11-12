# frozen_string_literal: true

class AddClaimedAtToInclamoOrderActions < ActiveRecord::Migration[7.1]
  def change
    # When a request took an open attempt to settle it (OrderActionRunner#claim!).
    # Kept apart from the outcome, so that a read meanwhile still sees a
    # running attempt as running.
    add_column :inclamo_order_actions, :claimed_at, :datetime
  end
end
