# frozen_string_literal: true

# Who in the account may give discounts from the presets. Separate from who
# may act on orders. Only administrators see and change it.
class Api::V1::Accounts::Inclamo::DiscountGrantsController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  def index
    render json: { members: members }
  end

  # Gives the right to the member with params[:user_id].
  def create
    member = find_member(params[:user_id])
    return head :not_found unless member

    unless member.administrator?
      ::Inclamo::DiscountGrant.find_or_create_by!(account_user_id: member.id) { |grant| grant.granted_by = Current.user }
    end
    render json: { members: members }
  end

  # Takes the right from the member with params[:id] (a user id).
  def destroy
    member = find_member(params[:id])
    return head :not_found unless member

    ::Inclamo::DiscountGrant.where(account_user_id: member.id).destroy_all
    render json: { members: members }
  end

  private

  def require_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden', message: I18n.t('inclamo.discounts.errors.forbidden') }, status: :forbidden
  end

  def find_member(user_id)
    Current.account.account_users.find_by(user_id: user_id)
  end

  def members
    grants = ::Inclamo::DiscountGrant.where(account_user_id: Current.account.account_users.select(:id)).index_by(&:account_user_id)
    Current.account.account_users.includes(:user).order(:id).map do |member|
      grant = grants[member.id]
      {
        user_id: member.user_id, name: member.user.name, email: member.user.email, role: member.role,
        can_give: member.administrator? || grant.present?,
        # Administrators always may; the switch does not apply to them.
        switchable: !member.administrator?,
        granted_at: grant&.created_at
      }
    end
  end
end
