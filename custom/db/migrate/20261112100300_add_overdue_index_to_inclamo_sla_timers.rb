# frozen_string_literal: true

# The timers whose missed target is still unmet (Inclamo::TeamQueues::Markers::OVERDUE).
# The SLA check looks for them on every run, and the table holds a row for
# every conversation a policy ever covered; without this the look is a scan
# of all of it. The set itself stays small: a timer leaves it when the target
# is met, the conversation is resolved or the timer stops.
class AddOverdueIndexToInclamoSlaTimers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  CONDITION = 'stopped_at IS NULL AND ((first_response_missed_at IS NOT NULL AND first_response_at IS NULL) ' \
              'OR (resolution_missed_at IS NOT NULL AND resolved_at IS NULL))'

  def change
    add_index :inclamo_sla_timers, :conversation_id, name: 'index_inclamo_sla_timers_overdue', where: CONDITION, algorithm: :concurrently,
                                                     if_not_exists: true
  end
end
