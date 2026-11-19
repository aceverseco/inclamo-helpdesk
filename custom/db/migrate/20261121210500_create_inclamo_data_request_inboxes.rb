# frozen_string_literal: true

# The "Data requests" inbox of an account (capability app-store-erasure): the
# API inbox, without members, where the store app's requests about one shopper
# become tickets for the account's administrators, and the one contact every
# such ticket belongs to (never the shopper: deleting the shopper must not
# delete the ticket). Made with the account's first request about a shopper.
#
# The row goes with the account or the inbox; a contact deleted by hand
# empties its column, and the next request makes a new one.
class CreateInclamoDataRequestInboxes < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_data_request_inboxes do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :contact, null: true, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
  end
end
