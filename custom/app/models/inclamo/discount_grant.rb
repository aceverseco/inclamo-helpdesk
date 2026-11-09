# frozen_string_literal: true

# The right to give discounts: an agent holding it may create a discount code
# from a preset. Separate from the order-actions role (Inclamo::OrderRole);
# either may be held without the other. Administrators need no row.
class Inclamo::DiscountGrant < ApplicationRecord
  belongs_to :account_user
  belongs_to :granted_by, class_name: 'User', optional: true

  validates :account_user_id, uniqueness: true

  # May this member of the account give discounts?
  def self.allows?(account_user)
    return false if account_user.nil?

    account_user.administrator? || exists?(account_user_id: account_user.id)
  end
end
