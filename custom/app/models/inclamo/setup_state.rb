# frozen_string_literal: true

class Inclamo::SetupState < ApplicationRecord
  belongs_to :account
  validates :account_id, uniqueness: true

  def overview
    connection = Inclamo::ShopifyConnection.find_by(account_id: account_id)
    ai = Inclamo::AiConnection.active_for(account_id)
    members = account.account_users.order(:id).map { |member| [member.id, member.user_id, member.role, Inclamo::ActionPermissions.for(member)] }
    policies = Inclamo::ActionPermissions::ACTIONS.map { |action| Inclamo::AiPolicy.for(account, action).as_json }
    digests = { 'staff' => Inclamo::Ai::OrderAuthority.digest(members), 'ai' => Inclamo::Ai::OrderAuthority.digest(policies) }
    reviewed = digests.to_h { |step, digest| [step, reviews[step] == digest] }
    channels = account.inboxes.where.not(id: ai&.phone_inbox_id).order(:id).pluck(:id, :name)
    checks = { 'store' => connection&.working? || false, 'channels' => channels.any?, 'staff' => reviewed['staff'], 'ai' => reviewed['ai'] }
    actions = Inclamo::OrderAction.where(account_id: account_id, outcome: 'accepted').order(id: :desc).limit(10)
    {
      checks: checks, review_digests: digests, ready: checks.values.all?, complete: completed_at.present? && checks.values.all?,
      completed_at: completed_at, store: connection && { domain: connection.shop_domain, state: connection.status, checked_at: connection.last_checked_at },
      channels: channels.map { |id, name| { id: id, name: name } }, members_count: members.size,
      ai_connected: ai.present?, ai_state: ai&.state,
      order_actions: actions.map { |action| { action: action.action, order_number: action.order_number, completed_at: action.completed_at,
                                            conversation_id: action.conversation&.display_id } }
    }
  end
end
