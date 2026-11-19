# frozen_string_literal: true

# The record of the store app's erasure requests (capability
# app-store-erasure): a store's erasure, and Shopify's two requests about one
# shopper. It outlives what it erased, so nothing here is a foreign key: the
# account, the conversation and the people it names may be gone.
#
# A store's row follows the store: scheduled, erasing, erased, or cancelled by
# a reinstall. A shopper's row is waiting, held or done; its email and phone
# are readable (encrypted at rest) only until it is done, the digests stay.
class CreateInclamoErasureRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_erasure_requests do |t|
      t.string :kind, null: false
      t.string :shop_domain, null: false
      # The account at the time of the request.
      t.bigint :account_id
      t.string :state, null: false
      t.datetime :received_at, null: false
      t.datetime :completed_at
      # A store's erasure: the users who belonged to the account only, chosen
      # before the account's memberships are destroyed; null until then.
      t.bigint :user_ids, array: true
      # A request about one shopper: its ticket, what Shopify named, and what
      # became of it.
      t.bigint :conversation_id
      t.text :email
      t.text :phone
      t.string :email_digest
      t.string :phone_digest
      t.string :order_ids, array: true, null: false, default: []
      t.datetime :delete_after
      t.text :hold_reason
      t.bigint :held_by_id
      t.datetime :held_at
      # team, automatic or store_erasure; done_by_id names the administrator.
      t.string :done_by
      t.bigint :done_by_id
      t.datetime :reminded_at
      t.timestamps
    end
    add_index :inclamo_erasure_requests, [:shop_domain, :kind, :state]
    add_index :inclamo_erasure_requests, [:kind, :state, :delete_after]
    add_index :inclamo_erasure_requests, [:state, :completed_at]
    add_index :inclamo_erasure_requests, [:account_id, :kind, :email_digest]
    add_index :inclamo_erasure_requests, [:account_id, :kind, :phone_digest]
    # One scheduled erasure per store, and one erasure under way per account.
    add_index :inclamo_erasure_requests, :shop_domain, unique: true, where: "kind = 'store' AND state = 'scheduled'",
                                                      name: 'index_inclamo_erasure_requests_scheduled_store'
    add_index :inclamo_erasure_requests, :account_id, unique: true, where: "kind = 'store' AND state = 'erasing'",
                                                      name: 'index_inclamo_erasure_requests_erasing_account'
    add_check_constraint :inclamo_erasure_requests, "kind IN ('store', 'shopper_erasure', 'shopper_data_request')",
                         name: 'inclamo_erasure_requests_kind'
    add_check_constraint :inclamo_erasure_requests,
                         "(kind = 'store' AND state IN ('scheduled', 'erasing', 'erased', 'cancelled')) OR " \
                         "(kind <> 'store' AND state IN ('waiting', 'held', 'done'))",
                         name: 'inclamo_erasure_requests_state'
  end
end
