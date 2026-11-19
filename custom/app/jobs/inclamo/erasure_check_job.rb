# frozen_string_literal: true

# The daily erasure run (capability app-store-erasure). Scheduled by the
# overlay once a day (Inclamo::Erasure.check_cron). It
# - starts the erasure of every store whose time has come and whose account is
#   suspended still (Inclamo::Erasure::Store.begin!);
# - alerts about every erasure that has been under way for more than a day,
#   and starts it again;
# - deletes the data of every shopper whose erasure ticket nobody deleted or
#   held before its date, in an active or a suspended account alike
#   (Inclamo::Erasure::ShopperActions.delete_automatically!);
# - writes the reminders that have come due in tickets about shoppers
#   (Inclamo::Erasure::Reminders);
# - removes the records of requests completed more than 90 days ago; a held
#   or waiting request is kept, whatever its age.
class Inclamo::ErasureCheckJob < ApplicationJob
  queue_as :scheduled_jobs

  STUCK_AFTER = 1.day

  def perform(now = Time.current)
    start_due(now)
    restart_stuck(now)
    delete_due_shoppers(now)
    remind(now)
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

  # One request that fails is reported and tried again at the next run; the
  # others are carried out all the same.
  def delete_due_shoppers(now)
    Inclamo::ErasureRequest.where(kind: 'shopper_erasure', state: 'waiting').where(delete_after: ..now).find_each do |request|
      Inclamo::Erasure::ShopperActions.delete_automatically!(request, now: now)
    rescue StandardError => e
      Rails.logger.error("[inclamo erasure] ALERT the automatic deletion of request #{request.id} (#{request.shop_domain}) failed: " \
                         "#{e.class}: #{e.message}; tried again at the next run")
    end
  end

  def remind(now)
    Inclamo::ErasureRequest.shoppers.where(state: %w[waiting held]).find_each do |request|
      Inclamo::Erasure::Reminders.remind!(request, now: now)
    rescue StandardError => e
      Rails.logger.error("[inclamo erasure] reminder of request #{request.id} not written: #{e.class}: #{e.message}")
    end
  end

  def remove_old(now)
    Inclamo::ErasureRequest.completed_before(now - Inclamo::ErasureRequest::KEEP).in_batches(of: 1000).delete_all
  end
end
