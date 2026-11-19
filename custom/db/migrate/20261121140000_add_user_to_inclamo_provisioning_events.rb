# frozen_string_literal: true

# The user a recorded attempt was about, where the helpdesk found one: a staff
# member's entry from the store app names a user by email (capability
# app-admin-entry), and the record keeps the user's id, never the email.
# Empty for every other attempt. Emptied when the user is deleted, so a
# store's erasure leaves no row naming its deleted users.
class AddUserToInclamoProvisioningEvents < ActiveRecord::Migration[7.1]
  def change
    add_reference :inclamo_provisioning_events, :user, null: true, index: true, foreign_key: { on_delete: :nullify }
  end
end
