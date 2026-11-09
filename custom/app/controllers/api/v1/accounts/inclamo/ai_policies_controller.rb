# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::AiPoliciesController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  def index
    render json: policies
  end

  def update
    return head :not_found unless ::Inclamo::ActionPermissions::ACTIONS.include?(params[:id])

    Current.account.with_lock do
      policy = ::Inclamo::AiPolicy.for(Current.account, params[:id])
      policy.update!(mode: params[:mode], limits: params[:limits].respond_to?(:to_unsafe_h) ? params[:limits].to_unsafe_h : {})
    end
    render json: policies
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'invalid_policy', message: e.record.errors.full_messages.join('. ') }, status: :unprocessable_entity
  end

  private

  def policies
    { policies: ::Inclamo::ActionPermissions::ACTIONS.map { |action| ::Inclamo::AiPolicy.for(Current.account, action).as_json },
      currency: ::Inclamo::ShopifyConnection.find_by(account_id: Current.account.id)&.shop_currency,
      allowed_states: ::Inclamo::AiPolicy::STATES }
  end

  def require_administrator
    head :forbidden unless Current.account_user&.administrator?
  end
end
