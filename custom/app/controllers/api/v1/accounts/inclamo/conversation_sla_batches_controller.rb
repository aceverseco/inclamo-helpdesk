# frozen_string_literal: true

# The SLA timers of several conversations in one answer, for the SLA badge on
# the rows of a conversation list (capability sla-badge). A conversation the
# member may not see, or that is not the account's, is left out of the answer:
# the list never learns whether it exists.
class Api::V1::Accounts::Inclamo::ConversationSlaBatchesController < Api::V1::Accounts::BaseController
  # A page of a list is 25 rows; several lists may ask together.
  MAX_IDS = 100
  # A timer is applied within moments of the conversation's creation. An older
  # conversation without one will not get one (its inbox joined a policy
  # later): it is not reported as on its way, or the list would keep asking.
  PENDING_FOR = 2.minutes

  # `ids`: display ids, as a list or separated by commas. Answers, per id the
  # member may see, the timer as the single read gives it (nil when none), and
  # in `pending` the ids whose timer is still being applied in the background.
  def index
    ids = display_ids
    return render json: { error: 'too_many_ids', limit: MAX_IDS }, status: :unprocessable_entity if ids.size > MAX_IDS

    conversations = visible(Current.account.conversations.where(display_id: ids))
    # The presenter's clock reads the inbox and its business hours.
    timers = ::Inclamo::SlaTimer.where(conversation_id: conversations.map(&:id))
                                .includes(conversation: { inbox: :working_hours }).index_by(&:conversation_id)
    render json: {
      timers: conversations.to_h { |conversation| [conversation.display_id.to_s, shown(timers[conversation.id])] },
      pending: conversations.reject { |conversation| timers.key?(conversation.id) }.select { |conversation| covered?(conversation) }.map(&:display_id)
    }
  end

  private

  def display_ids
    raw = params[:ids]
    raw = raw.split(',') if raw.is_a?(String)
    Array(raw).filter_map { |id| Integer(id.to_s, 10, exception: false) }.select(&:positive?).uniq
  end

  # Chatwoot's own rule for opening a conversation. It reads the inbox and the
  # team only, so it is asked once for each pair of them.
  def visible(conversations)
    asked = {}
    conversations.select do |conversation|
      key = [conversation.inbox_id, conversation.team_id]
      asked.fetch(key) { asked[key] = ConversationPolicy.new(pundit_user, conversation).show? }
    end
  end

  def shown(timer)
    timer && ::Inclamo::Sla::TimerPresenter.new(timer).as_json
  end

  # As Inclamo::SlaPolicy.covering, with the account's policies read once.
  def covered?(conversation)
    return false if conversation.created_at < PENDING_FOR.ago

    @policies ||= ::Inclamo::SlaPolicy.where(account_id: Current.account.id).ordered.to_a
    @policies.any? { |policy| policy.created_at <= conversation.created_at && policy.covers?(conversation.inbox_id) }
  end
end
