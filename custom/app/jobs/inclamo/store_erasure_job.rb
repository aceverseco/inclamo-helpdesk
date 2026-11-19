# frozen_string_literal: true

# Destroys the account of a store whose erasure has come due
# (Inclamo::Erasure::Store). Chatwoot's deletion of an account leaves part of
# the work to background jobs, so the erasure is complete only once no table
# names the account or its deleted users: until then this job tries again,
# a little later each time, for about a day. When it gives up, the record
# stays `erasing` and an alert is logged for the operator; the daily run
# (Inclamo::ErasureCheckJob) alerts again and starts it once more every day.
class Inclamo::StoreErasureJob < ApplicationJob
  queue_as :scheduled_jobs

  ATTEMPTS = 20
  # 5 s, 10 s, 20 s, ... at most an hour between two attempts.
  WAIT = ->(executions) { [5 * (2**[executions - 1, 10].min), 3600].min }

  retry_on Inclamo::Erasure::Store::NotFinished, wait: WAIT, attempts: ATTEMPTS do |job, error|
    Rails.logger.error("[inclamo erasure] ALERT #{error.message}; gave up after #{ATTEMPTS} attempts (record #{job.arguments.first})")
  end

  def perform(record_id)
    record = Inclamo::ErasureRequest.stores.find_by(id: record_id, state: 'erasing')
    return unless record

    # Shows the daily run that the erasure is being worked on.
    record.touch
    Inclamo::Erasure::Store.new(record).run
  end
end
