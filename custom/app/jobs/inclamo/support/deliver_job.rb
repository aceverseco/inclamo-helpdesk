# frozen_string_literal: true

class Inclamo::Support::DeliverJob < ApplicationJob
  queue_as :low

  def perform(id)
    submission = Inclamo::Support::Submission.find_by(id: id)
    return unless submission

    submission.with_lock do
      return if submission.state == 'delivered' || submission.lease_until&.future? || submission.next_attempt_at&.future?

      submission.update!(lease_until: 3.minutes.from_now, attempts: submission.attempts + 1)
    end
    Inclamo::Support::Transport.new.deliver!(submission)
    Inclamo::Support::SyncJob.perform_later
  rescue Inclamo::Support::Rejected
    # Central refusing this installation is retried like an outage: intake may
    # be halted on purpose, with outboxes kept queued until it resumes.
    retry_later(submission)
  rescue Inclamo::Support::Unauthorized
    submission&.update!(state: 'failed', error_code: 'access_changed', lease_until: nil, next_attempt_at: nil)
  rescue Inclamo::Support::Conflict
    submission&.update!(state: 'failed', error_code: 'submission_conflict', lease_until: nil, next_attempt_at: nil)
  rescue StandardError => error
    Rails.logger.warn("Inclamo support delivery failed: #{error.class}")
    retry_later(submission)
  end

  private

  def retry_later(submission)
    return unless submission

    delay = [15 * (2**[submission.attempts, 8].min), 3600].min
    state = submission.uploads.exists? ? 'attachments_pending' : 'queued'
    submission.update!(state: state, error_code: 'support_unavailable', lease_until: nil, next_attempt_at: delay.seconds.from_now)
  end
end
