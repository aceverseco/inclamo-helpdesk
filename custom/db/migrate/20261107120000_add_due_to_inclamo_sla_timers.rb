# frozen_string_literal: true

class AddDueToInclamoSlaTimers < ActiveRecord::Migration[7.1]
  def change
    # The deadlines of a timer as last computed, with the moment they were
    # computed: the periodic check leaves a business-hours timer alone until
    # its deadline instead of working it out again every run. Computed again
    # when the inbox's business hours change; the sidebar never reads them.
    add_column :inclamo_sla_timers, :first_response_due_at, :datetime
    add_column :inclamo_sla_timers, :resolution_due_at, :datetime
    add_column :inclamo_sla_timers, :due_computed_at, :datetime
  end
end
