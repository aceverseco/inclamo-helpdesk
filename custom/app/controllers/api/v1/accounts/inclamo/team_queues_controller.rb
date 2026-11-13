# frozen_string_literal: true

# The account's team queues (capability team-queues). Every staff member
# reads the visible ones with their own counts; administrators rename,
# reorder, hide and restore them.
class Api::V1::Accounts::Inclamo::TeamQueuesController < Api::V1::Accounts::BaseController
  before_action :require_administrator, except: [:index, :sla_overview]
  before_action :set_queue, only: [:update, :restore]

  # `all=1`, for administrators, adds the hidden queues (without a count).
  def index
    everything = administrator? && ActiveModel::Type::Boolean.new.cast(params[:all])
    render json: listing(everything ? queues : queues.visible)
  end

  def update
    if params.key?(:name)
      return refuse(:name_invalid) unless params[:name].is_a?(String)

      @queue.name = params[:name].strip
    end
    if params.key?(:hidden)
      hidden = [true, false].include?(params[:hidden]) || params[:hidden].is_a?(String) ? ActiveModel::Type::Boolean.new.cast(params[:hidden]) : nil
      return refuse(:hidden_invalid) if hidden.nil?

      @queue.hidden = hidden
    end
    return refuse(@queue.errors.of_kind?(:hidden, :too_many_visible) ? :too_many_visible : :name_invalid) unless @queue.save

    render json: listing(queues)
  end

  # The "SLA overview" widget: the visible queues with their conversations
  # counted as overdue, soon and other, for this member. The answer is kept
  # for half a minute per member: every open workspace asks once a minute.
  SLA_OVERVIEW_FOR = 30.seconds

  def sla_overview
    # The numbers are a staff member's: a bot's token has none.
    return head :forbidden unless Current.user.is_a?(User)

    key = "inclamo:sla_overview:#{Current.account.id}:#{Current.user.id}"
    render json: Rails.cache.fetch(key, expires_in: SLA_OVERVIEW_FOR) { ::Inclamo::TeamQueues::SlaOverview.call(Current.account, Current.user) }
  end

  # `ids`: every queue of the account, in the new order.
  def reorder
    ids = params[:ids]
    return refuse(:order_incomplete) unless ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) || (id.is_a?(String) && id.match?(/\A\d+\z/)) }

    ids = ids.map(&:to_i)
    return refuse(:order_incomplete) unless ids.sort == queues.pluck(:id).sort

    ::Inclamo::TeamQueue.transaction do
      ids.each_with_index { |id, index| queues.where(id: id).update_all(position: index + 1, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
    end
    render json: listing(queues)
  end

  # The name, membership and place a ready queue shipped with: its place among
  # the queues as they are ordered now, every queue numbered anew so that no
  # two share a position. Whether it is hidden stays as the administrator set it.
  def restore
    return refuse(:not_ready) unless @queue.ready?

    key = @queue.key
    ::Inclamo::TeamQueue.transaction do
      @queue.update!(name: ::Inclamo::TeamQueues.shipped_name(key), query: ::Inclamo::TeamQueues.shipped_query(key))
      ::Inclamo::TeamQueues.place!(@queue)
    end
    render json: listing(queues)
  end

  private

  def queues
    ::Inclamo::TeamQueue.where(account_id: Current.account.id).ordered
  end

  # A queue that cannot be counted is listed with no count (Inclamo::TeamQueues.count).
  def listing(scope)
    {
      queues: scope.map { |queue| queue.as_json(count: queue.hidden? ? nil : ::Inclamo::TeamQueues.count(queue, Current.user)) },
      limit: ::Inclamo::TeamQueue::VISIBLE_LIMIT
    }
  end

  def set_queue
    @queue = queues.find_by(id: params[:id])
    head :not_found unless @queue
  end

  def administrator?
    Current.account_user&.administrator?
  end

  def require_administrator
    refuse(:forbidden, :forbidden) unless administrator?
  end

  def refuse(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("inclamo.team_queues.errors.#{code}") }, status: status
  end
end
