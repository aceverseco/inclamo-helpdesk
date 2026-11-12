# frozen_string_literal: true

# Gives the ready team queues and saved replies to accounts that still lack
# them: an account whose installation failed when it was created or during
# the upgrade (Inclamo::Presets). Scheduled by the overlay every ten minutes;
# with nothing to repair it is one query.
class Inclamo::PresetsRepairJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Inclamo::Presets.repair
  end
end
