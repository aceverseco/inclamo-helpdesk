# frozen_string_literal: true

# Who in the account may act on orders. Only administrators see and change it.
class Api::V1::Accounts::Inclamo::OrderRolesController < Api::V1::Accounts::BaseController
  include ::Inclamo::RequireAdministrator
  require_administrator 'inclamo.order_roles.errors.forbidden'

  def index
    render json: { members: members }
  end

  # Gives the role to the member with params[:user_id].
  def create
    member = find_member(params[:user_id])
    return head :not_found unless member

    unless member.administrator?
      ::Inclamo::OrderRole.find_or_create_by!(account_user_id: member.id) { |role| role.granted_by = Current.user }
    end
    render json: { members: members }
  end

  # Takes the role from the member with params[:id] (a user id).
  def destroy
    member = find_member(params[:id])
    return head :not_found unless member

    ::Inclamo::OrderRole.where(account_user_id: member.id).destroy_all
    render json: { members: members }
  end

  private

  def find_member(user_id)
    Current.account.account_users.find_by(user_id: user_id)
  end

  def members
    roles = ::Inclamo::OrderRole.where(account_user_id: Current.account.account_users.select(:id)).index_by(&:account_user_id)
    Current.account.account_users.includes(:user).order(:id).map do |member|
      role = roles[member.id]
      {
        user_id: member.user_id, name: member.user.name, email: member.user.email, role: member.role,
        can_act: member.administrator? || role.present?,
        # Administrators act by their role; the switch does not apply to them.
        switchable: !member.administrator?,
        granted_at: role&.created_at
      }
    end
  end
end
