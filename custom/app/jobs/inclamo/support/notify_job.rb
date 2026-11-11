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
      return unless recipient.active? && recipient.verified_at && !recipient.source.revoked_at && message&.outgoing? && Inclamo::Support::Feed.public?(message)

      Inclamo::Support::Mailer.notification(delivery).deliver_now
      delivery.update!(delivered_at: Time.current, attempts: delivery.attempts + 1)
    end
  rescue StandardError => error
    Rails.logger.warn("Inclamo support notification failed: #{error.class}")
    delivery&.update!(attempts: delivery.attempts + 1, next_attempt_at: [30 * 2**[delivery.attempts, 7].min, 3600].min.seconds.from_now)
  end
end
