# frozen_string_literal: true

class Inclamo::Support::DispatchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Inclamo::Support::Submission.where(state: %w[queued attachments_pending]).where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current).find_each do |submission|
      Inclamo::Support::DeliverJob.perform_later(submission.id)
    end
    Inclamo::Support::SyncJob.perform_later
    if Inclamo::Support.central?
      Inclamo::Support::CentralRequest.find_each { |request| Inclamo::Support::ReconcileJob.perform_later(request.id) }
      Inclamo::Support::Delivery.where(delivered_at: nil).where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current).find_each do |delivery|
        Inclamo::Support::NotifyJob.perform_later(delivery.id)
      end
    end
    Inclamo::Support::Files.clean_staging!
  end
end
