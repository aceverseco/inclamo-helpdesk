# frozen_string_literal: true

class Inclamo::Support::NotifyJob < ApplicationJob
  queue_as :low

  def perform(id)
    delivery = Inclamo::Support::Delivery.find_by(id: id)
    return unless delivery

    delivery.with_lock do
      return if delivery.delivered_at || delivery.next_attempt_at&.future?
      recipient = delivery.recipient.reload
      message = ::Message.find_by(id: delivery.message_id, conversation_id: delivery.central_request.conversation_id)
      reason = unsendable(recipient, message)
      # None of these passes for this reply: an author who opts in again is
      # verified again, and Recipients.notify! skips replies older than that.
      # The record is removed so that dispatch stops picking it up every minute.
      next close(delivery, reason) if reason

      Inclamo::Support::Mailer.notification(delivery).deliver_now
      delivery.update!(delivered_at: Time.current, attempts: delivery.attempts + 1)
    end
  rescue StandardError => error
    Rails.logger.warn("Inclamo support notification failed: #{error.class}")
    delivery&.update!(attempts: delivery.attempts + 1, next_attempt_at: [30 * 2**[delivery.attempts, 7].min, 3600].min.seconds.from_now)
  end

  private

  def unsendable(recipient, message)
    return 'recipient_inactive' unless recipient.active?
    return 'recipient_unverified' unless recipient.verified_at
    return 'source_revoked' if recipient.source.revoked_at

    'message_withdrawn' unless message&.outgoing? && Inclamo::Support::Feed.public?(message)
  end

  def close(delivery, reason)
    Rails.logger.info("Inclamo support notification #{delivery.id} closed: #{reason}")
    delivery.destroy!
  end
end
