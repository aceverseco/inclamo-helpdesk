# frozen_string_literal: true

class Inclamo::Support::SyncJob < ApplicationJob
  queue_as :low

  def perform(request_id = nil)
    installation = Inclamo::Support::Installation.find_by(purpose: 'support')
    return unless installation&.source_id

    installation.with_lock do
      return if installation.next_sync_at&.future? || installation.sync_lease_until&.future?

      installation.update!(sync_lease_until: 2.minutes.from_now)
    end
    transport = Inclamo::Support::Transport.new
    requested = Inclamo::Support::Request.find_by(id: request_id) if request_id
    transport.reconcile(requested) if requested
    begin
      transport.sync_recipients
    rescue StandardError => error
      # Recipient maintenance is retried at the next sync, independently of replies.
      Rails.logger.warn("Inclamo support recipient sync failed: #{error.class}")
    end
    5.times do
      batch = transport.events(installation.cursor)
      installation.with_lock do
        batch.fetch('events').each { |event| Inclamo::Support::Feed.import!(event) }
        installation.update!(cursor: batch.fetch('cursor'))
      end
      break unless batch['more']
    end
    installation.update!(failures: 0, next_sync_at: 8.seconds.from_now, sync_lease_until: nil)
  rescue StandardError => error
    Rails.logger.warn("Inclamo support synchronization failed: #{error.class}")
    return unless installation

    failures = installation.failures + 1
    installation.update!(failures: failures, next_sync_at: [10 * 2**[failures, 8].min, 3600].min.seconds.from_now, sync_lease_until: nil)
  end
end
