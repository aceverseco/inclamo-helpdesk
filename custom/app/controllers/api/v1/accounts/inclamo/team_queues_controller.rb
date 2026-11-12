# frozen_string_literal: true

# The account's team queues (capability team-queues). Every staff member
# reads the visible ones with their own counts; administrators rename,
# reorder, hide and restore them.
class Api::V1::Accounts::Inclamo::TeamQueuesController < Api::V1::Accounts::BaseController
  before_action :require_administrator, except: :index
  before_action :set_queue, only: [:update, :restore]

  # `all=1`, for administrators, adds the hidden queues (without a count).
  def index
    everything = administrator? && ActiveModel::Type::Boolean.new.cast(params[:all])
    render json: listing(everything ? queues : queues.visible)
  end

  def update
    @queue.name = params[:name].to_s.strip if params.key?(:name)
    @queue.hidden = ActiveModel::Type::Boolean.new.cast(params[:hidden]) if params.key?(:hidden)
    return refuse(@queue.errors.of_kind?(:hidden, :too_many_visible) ? :too_many_visible : :name_invalid) unless @queue.save

    render json: listing(queues)
  end

  # `ids`: every queue of the account, in the new order.
  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    return refuse(:order_incomplete) unless ids.sort == queues.pluck(:id).sort

    ::Inclamo::TeamQueue.transaction do
      ids.each_with_index { |id, index| queues.where(id: id).update_all(position: index + 1, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
    end
    render json: listing(queues)
  end

  # The name, place and membership a ready queue shipped with. Whether it is
  # hidden stays as the administrator set it.
  def restore
    return refuse(:not_ready) unless @queue.ready?

    key = @queue.key
    @queue.update!(name: ::Inclamo::TeamQueues.shipped_name(key), position: ::Inclamo::TeamQueues.shipped_position(key),
                   query: ::Inclamo::TeamQueues.shipped_query(key))
    render json: listing(queues)
  end

  private

  def queues
    ::Inclamo::TeamQueue.where(account_id: Current.account.id).ordered
  end

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
