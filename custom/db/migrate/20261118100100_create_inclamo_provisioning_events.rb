# frozen_string_literal: true

# The record of provisioning attempts: when, for which store, how it ended and
# under which request id. It holds no email, name, signature or request body.
# Rows older than 90 days are removed by Inclamo::ProvisioningEventsCleanupJob.
class CreateInclamoProvisioningEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_provisioning_events do |t|
      t.string :shop_domain
      t.string :outcome, null: false
      t.string :request_id
      t.datetime :created_at, null: false
    end
    add_index :inclamo_provisioning_events, :created_at
    add_index :inclamo_provisioning_events, [:shop_domain, :created_at]
  end
end
