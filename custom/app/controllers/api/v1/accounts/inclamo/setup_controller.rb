# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::SetupController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  def show
    render json: state.overview
  end

  def update
    Current.account.with_lock do
      record = state
      step = params[:step]
      snapshot = record.overview
      unless %w[staff ai].include?(step) && snapshot[:review_digests][step] == params[:digest]
        return render json: { error: 'review_changed' }, status: :conflict
      end

      record.update!(reviews: record.reviews.merge(step => params[:digest]), completed_at: nil)
    end
    render json: state.overview
  end

  def complete
    Current.account.with_lock do
      record = state
      snapshot = record.overview
      return render json: snapshot.merge(error: 'setup_incomplete'), status: :conflict unless snapshot[:ready]

      record.update!(completed_at: Time.current)
    end
    render json: state.overview
  end

  private

  def state
    ::Inclamo::SetupState.find_or_initialize_by(account_id: Current.account.id)
  end

  def require_administrator
    head :forbidden unless Current.account_user&.administrator?
  end
end
