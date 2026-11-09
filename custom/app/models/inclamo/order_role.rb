# frozen_string_literal: true

# The order-actions role: an agent holding it may cancel, refund, change the
# address of and replace orders. Administrators need no row. Chatwoot's own
# custom roles belong to its paid edition and are not used.
class Inclamo::OrderRole < ApplicationRecord
  belongs_to :account_user
  belongs_to :granted_by, class_name: 'User', optional: true

  validates :account_user_id, uniqueness: true
  validate :known_permissions

  # May this member of the account perform order actions?
  def self.allows?(account_user, action = nil)
    grants = Inclamo::ActionPermissions.for(account_user)
    action ? grants[action.to_s] == true : Inclamo::ActionPermissions::ORDER_ACTIONS.any? { |name| grants[name] }
  end

  private

  def known_permissions
    return if permissions.is_a?(Array) && (permissions - Inclamo::ActionPermissions::ORDER_ACTIONS).empty? && permissions.uniq == permissions

    errors.add(:permissions, 'must contain unique known order actions')
  end
end
