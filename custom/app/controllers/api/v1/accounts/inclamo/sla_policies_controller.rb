# frozen_string_literal: true

# SLA policies of the account and their summary. Only administrators see and
# change them. Targets are in seconds; the page offers minutes, hours and days.
class Api::V1::Accounts::Inclamo::SlaPoliciesController < Api::V1::Accounts::BaseController
  include ::Inclamo::RequireAdministrator
  require_administrator 'inclamo.sla.errors.forbidden'
  before_action :find_policy, only: [:update, :destroy]

  def index
    render json: { policies: policies, inboxes: inboxes }
  end

  def create
    policy = scope.new(policy_params)
    return render json: invalid(policy), status: :unprocessable_entity unless policy.save

    render json: { policy: present(policy) }, status: :created
  end

  def update
    return render json: invalid(@policy), status: :unprocessable_entity unless @policy.update(policy_params)

    render json: { policy: present(@policy) }
  end

  def destroy
    @policy.destroy!
    head :no_content
  end

  # params[:ids]: the account's policy ids in their new order.
  def reorder
    ::Inclamo::SlaPolicy.reorder!(Current.account, params[:ids])
    render json: { policies: policies }
  end

  # GET .../summary?days=7 (or 30)
  def summary
    days = ::Inclamo::Sla::Summary::DAYS.include?(params[:days].to_i) ? params[:days].to_i : ::Inclamo::Sla::Summary::DAYS.first
    render json: { days: days, policies: ::Inclamo::Sla::Summary.new(Current.account, days: days).as_json }
  end

  private

  def scope
    ::Inclamo::SlaPolicy.where(account_id: Current.account.id)
  end

  def find_policy
    @policy = scope.find_by(id: params[:id])
    head :not_found unless @policy
  end

  def policy_params
    params.permit(:name, :first_response_seconds, :resolution_seconds, :business_hours_only, :all_inboxes, inbox_ids: [])
  end

  def policies
    scope.ordered.map { |policy| present(policy) }
  end

  def present(policy)
    policy.slice(:id, :name, :position, :first_response_seconds, :resolution_seconds, :business_hours_only, :all_inboxes, :inbox_ids)
  end

  def inboxes
    Current.account.inboxes.order(:name).map { |inbox| { id: inbox.id, name: inbox.name, business_hours: inbox.working_hours_enabled? } }
  end

  def invalid(policy)
    { error: 'invalid', messages: policy.errors.map(&:message), fields: policy.errors.attribute_names.map(&:to_s) }
  end
end
