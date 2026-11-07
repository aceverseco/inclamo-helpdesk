# frozen_string_literal: true

# The periodic check for missed SLA targets (design D4). Scheduled by the
# overlay every INCLAMO_SLA_CHECK_SECONDS (60 by default).
class Inclamo::SlaCheckJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Inclamo::Sla::Timers.check_due!
  end
end
