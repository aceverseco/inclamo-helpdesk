# frozen_string_literal: true

# The store's erasure on the store app's request (capability
# app-store-erasure). A suspended account is given the time after which it is
# destroyed (`erase_after`); a store whose account is being destroyed is
# `erasing`, and afterwards `erased`, with the time (`erased_at`). From
# `erasing` on, the row names no account: the store keeps only its domain, the
# fact of the erasure and its time, and the account being destroyed is named
# by the erasure's own record (inclamo_erasure_requests).
class AddErasureToInclamoProvisionedAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :inclamo_provisioned_accounts, :erase_after, :datetime
    add_column :inclamo_provisioned_accounts, :erased_at, :datetime
    remove_check_constraint :inclamo_provisioned_accounts, name: 'inclamo_provisioned_accounts_state'
    add_check_constraint :inclamo_provisioned_accounts, "state IN ('active', 'suspended', 'erasing', 'erased')",
                         name: 'inclamo_provisioned_accounts_state'
    add_check_constraint :inclamo_provisioned_accounts, "state NOT IN ('erasing', 'erased') OR account_id IS NULL",
                         name: 'inclamo_provisioned_accounts_erased_account'
    add_index :inclamo_provisioned_accounts, :erase_after, where: 'erase_after IS NOT NULL'
  end

  # Possible only while no store is erasing or erased.
  def down
    remove_index :inclamo_provisioned_accounts, :erase_after
    remove_check_constraint :inclamo_provisioned_accounts, name: 'inclamo_provisioned_accounts_erased_account'
    remove_check_constraint :inclamo_provisioned_accounts, name: 'inclamo_provisioned_accounts_state'
    add_check_constraint :inclamo_provisioned_accounts, "state IN ('active', 'suspended')", name: 'inclamo_provisioned_accounts_state'
    remove_column :inclamo_provisioned_accounts, :erased_at
    remove_column :inclamo_provisioned_accounts, :erase_after
  end
end
