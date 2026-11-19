# frozen_string_literal: true

# The account a recorded attempt was made for, where the helpdesk knows it: a
# request for a store key names it (capability app-store-access). Empty for
# the store app's own calls, which name a store. Emptied when the account goes.
class AddAccountToInclamoProvisioningEvents < ActiveRecord::Migration[7.1]
  def change
    add_reference :inclamo_provisioning_events, :account, null: true, index: true, foreign_key: { on_delete: :nullify }
  end
end
