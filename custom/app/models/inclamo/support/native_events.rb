# frozen_string_literal: true

module Inclamo::Support::NativeEvents
  extend ActiveSupport::Concern

  included do
    after_commit :inclamo_support_changed, on: [:create, :update, :destroy]
  end

  private

  def inclamo_support_changed
    return unless Inclamo::Support.central?

    conversation_id = is_a?(::Conversation) ? id : self.conversation_id
    mapping = Inclamo::Support::CentralRequest.find_by(conversation_id: conversation_id)
    Inclamo::Support::ReconcileJob.perform_later(mapping.id) if mapping
  rescue StandardError => error
    # Reconciliation repairs missed hooks; support must never interrupt customer work.
    Rails.logger.warn("Inclamo support event enqueue failed: #{error.class}")
  end
end
