# frozen_string_literal: true

# Removes records of provisioning attempts older than 90 days. Scheduled by the
# overlay once a day.
class Inclamo::ProvisioningEventsCleanupJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Inclamo::ProvisioningEvent.expired.in_batches(of: 1000).delete_all
  end
end
