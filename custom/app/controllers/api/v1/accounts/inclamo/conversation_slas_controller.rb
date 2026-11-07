# frozen_string_literal: true

# The SLA timer of one conversation, for the "SLA" section of its sidebar.
# Open to every member who may see the conversation.
class Api::V1::Accounts::Inclamo::ConversationSlasController < Api::V1::Accounts::Conversations::BaseController
  # `pending`: no timer yet, but a policy covers the conversation, so one is
  # being applied in the background and the sidebar asks again shortly.
  def show
    timer = ::Inclamo::SlaTimer.find_by(conversation_id: @conversation.id)
    render json: { timer: timer && ::Inclamo::Sla::TimerPresenter.new(timer).as_json,
                   pending: timer.nil? && ::Inclamo::SlaPolicy.covering(@conversation).present? }
  end
end
