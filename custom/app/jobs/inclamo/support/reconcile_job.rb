# frozen_string_literal: true

class Inclamo::Support::ReconcileJob < ApplicationJob
  queue_as :low

  def perform(id)
    return unless Inclamo::Support.central?

    mapping = Inclamo::Support::CentralRequest.find_by(id: id)
    Inclamo::Support::Feed.reconcile!(mapping) if mapping
  end
end
