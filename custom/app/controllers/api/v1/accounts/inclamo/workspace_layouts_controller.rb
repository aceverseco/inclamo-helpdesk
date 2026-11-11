# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::WorkspaceLayoutsController < Api::V1::Accounts::BaseController
  before_action :require_administrator, only: [:administration, :administer]
  rescue_from ::Inclamo::WorkspaceLayout::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from ::Inclamo::WorkspaceLayout::Conflict do
    render json: { error: 'layout_conflict' }, status: :conflict
  end

  def show
    render json: service.read
  end

  def update
    render json: service.save!(layout: layout, expected: params[:revision])
  end

  def destroy
    render json: service.save!(layout: nil, expected: params[:revision], reset: true)
  end

  def administration
    render json: service.administration
  end

  def administer
    render json: service.administer!(layout: layout, expected: params[:revision], target: params[:target],
                                    user_id: params[:user_id], confirmed_count: params[:confirmed_count])
  end

  private

  def service
    @service ||= ::Inclamo::WorkspaceLayout.new(Current.account_user)
  end

  def layout
    # The service validates the complete bounded shape (including unknown keys).
    raise ::Inclamo::WorkspaceLayout::Invalid, 'invalid_layout' unless params[:layout].is_a?(ActionController::Parameters)

    params[:layout].to_unsafe_h
  end

  def require_administrator
    head :forbidden unless Current.account_user&.administrator?
  end
end
