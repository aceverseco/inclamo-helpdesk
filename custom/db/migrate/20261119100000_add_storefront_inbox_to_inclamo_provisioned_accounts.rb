# frozen_string_literal: true

# Which inbox of a provisioned account is the store's storefront chat
# (capability app-storefront-chat). Empty when the account has none: it was
# never made, or the team deleted it, and then the database empties the column
# itself, so a deleted inbox is never reported as there.
class AddStorefrontInboxToInclamoProvisionedAccounts < ActiveRecord::Migration[7.1]
  def change
    add_reference :inclamo_provisioned_accounts, :storefront_inbox, null: true, index: { unique: true },
                                                                    foreign_key: { to_table: :inboxes, on_delete: :nullify }
  end
end
