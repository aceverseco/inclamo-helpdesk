# frozen_string_literal: true

# The daily erasure run (capability app-store-erasure). Scheduled by the
# overlay once a day (Inclamo::Erasure.check_cron). It
# - starts the erasure of every store whose time has come and whose account is
#   suspended still (Inclamo::Erasure::Store.begin!);
# - alerts about every erasure that has been under way for more than a day,
#   and starts it again;
# - removes the records of requests completed more than 90 days ago.
class Inclamo::ErasureCheckJob < ApplicationJob
  queue_as :scheduled_jobs

  STUCK_AFTER = 1.day

  def perform(now = Time.current)
    start_due(now)
    restart_stuck(now)
    remove_old(now)
  end

  private

  def start_due(now)
    Inclamo::ProvisionedAccount.where(state: 'suspended').where(erase_after: ..now).find_each do |row|
      record = Inclamo::Erasure::Store.begin!(row, now: now)
      Inclamo::StoreErasureJob.perform_later(record.id) if record
    end
  end

  def restart_stuck(now)
    Inclamo::ErasureRequest.stores.where(state: 'erasing').where(updated_at: ...(now - STUCK_AFTER)).find_each do |record|
      Rails.logger.error("[inclamo erasure] ALERT the erasure of #{record.shop_domain} (record #{record.id}) has been under way " \
                         "since #{record.updated_at.utc.iso8601}; started again")
      Inclamo::StoreErasureJob.perform_later(record.id)
    end
  end

  def remove_old(now)
    Inclamo::ErasureRequest.completed_before(now - Inclamo::ErasureRequest::KEEP).in_batches(of: 1000).delete_all
  end
end
