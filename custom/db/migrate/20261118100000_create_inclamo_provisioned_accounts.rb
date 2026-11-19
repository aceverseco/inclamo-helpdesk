# frozen_string_literal: true

# The account a Shopify store was given on the store app's request (capability
# app-provisioned-account). One row per store, one store per account: both are
# unique indexes, so two requests for one new store end with one account.
class CreateInclamoProvisionedAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_provisioned_accounts do |t|
      # The store's permanent myshopify.com domain, always lower-case.
      t.string :shop_domain, null: false
      # Empty only inside the transaction that creates the account: the row is
      # inserted first, so a concurrent request waits on the unique index.
      t.references :account, null: true, index: false, foreign_key: { on_delete: :cascade }
      t.string :state, null: false, default: 'active'
      t.timestamps
    end
    add_index :inclamo_provisioned_accounts, :shop_domain, unique: true
    add_index :inclamo_provisioned_accounts, :account_id, unique: true
    add_check_constraint :inclamo_provisioned_accounts, 'shop_domain = lower(shop_domain)',
                         name: 'inclamo_provisioned_accounts_domain_lower'
    add_check_constraint :inclamo_provisioned_accounts, "state IN ('active', 'suspended')",
                         name: 'inclamo_provisioned_accounts_state'
  end
end
