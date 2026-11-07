# frozen_string_literal: true

# The order-actions role: an agent holding it may cancel, refund, change the
# address of and replace orders. Administrators need no row. Chatwoot's own
# custom roles belong to its paid edition and are not used.
class Inclamo::OrderRole < ApplicationRecord
  belongs_to :account_user
  belongs_to :granted_by, class_name: 'User', optional: true

  validates :account_user_id, uniqueness: true

  # May this member of the account perform order actions?
  def self.allows?(account_user)
    return false if account_user.nil?

    account_user.administrator? || exists?(account_user_id: account_user.id)
  end
end
