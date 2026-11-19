# frozen_string_literal: true

# The store app's address for a store's key requests, as the app's provisioning
# request gives it (capability app-provisioned-account). Empty when the app
# never named one: the installation's configured address applies then.
class AddStoreAccessUrlToInclamoProvisionedAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :inclamo_provisioned_accounts, :store_access_url, :string, null: true
  end
end
