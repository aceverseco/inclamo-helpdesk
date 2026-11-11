# frozen_string_literal: true

class CreateInclamoSupport < ActiveRecord::Migration[7.1]
  def change
    create_table :inclamo_support_installations do |t|
      t.string :purpose, null: false, default: 'support', index: { unique: true }
      t.text :private_key, null: false
      t.text :public_key, null: false
      t.string :source_id
      t.string :endpoint
      t.bigint :cursor, null: false, default: 0
      t.datetime :next_sync_at
      t.datetime :sync_lease_until
      t.integer :failures, null: false, default: 0
      t.timestamps
    end
    create_table :inclamo_support_requests do |t|
      t.string :reference, null: false, index: { unique: true }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :author_key, null: false
      t.jsonb :author_snapshot, null: false, default: {}
      t.string :category, null: false
      t.jsonb :context, null: false, default: {}
      t.string :central_reference
      t.string :status, null: false, default: 'open'
      t.bigint :last_reply_id, null: false, default: 0
      t.timestamps
    end
    create_table :inclamo_support_submissions do |t|
      t.references :request, null: false, foreign_key: { to_table: :inclamo_support_requests, on_delete: :cascade }
      t.string :uuid, null: false, index: { unique: true }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.jsonb :actor_snapshot, null: false, default: {}
      t.text :body, null: false
      t.string :state, null: false, default: 'queued'
      t.string :error_code
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :lease_until
      t.jsonb :staged_files, null: false, default: {}
      t.string :central_message_id
      t.timestamps
    end
    add_index :inclamo_support_submissions, [:state, :next_attempt_at]
    create_table :inclamo_support_messages do |t|
      t.references :request, null: false, foreign_key: { to_table: :inclamo_support_requests, on_delete: :cascade }
      t.string :central_message_id, null: false
      t.string :submission_uuid
      t.string :direction, null: false
      t.jsonb :actor, null: false, default: {}
      t.text :body
      t.jsonb :files, null: false, default: []
      t.datetime :sent_at
      t.timestamps
    end
    add_index :inclamo_support_messages, [:request_id, :central_message_id], unique: true, name: 'inclamo_support_message_identity'
    create_table :inclamo_support_reads do |t|
      t.references :request, null: false, foreign_key: { to_table: :inclamo_support_requests, on_delete: :cascade }
      t.references :account_user, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :last_reply_id, null: false, default: 0
      t.timestamps
    end
    add_index :inclamo_support_reads, [:request_id, :account_user_id], unique: true, name: 'inclamo_support_reader'
    create_table :inclamo_support_sources do |t|
      t.string :reference, null: false, index: { unique: true }
      t.string :fingerprint, null: false, index: { unique: true }
      t.text :public_key, null: false
      t.string :base_url, null: false
      t.boolean :hosted, null: false, default: false
      t.datetime :revoked_at
      t.timestamps
    end
    create_table :inclamo_support_central_requests do |t|
      t.references :source, null: false, foreign_key: { to_table: :inclamo_support_sources, on_delete: :cascade }
      t.string :reference, null: false, index: { unique: true }
      t.string :local_reference, null: false
      t.string :account_key, null: false
      t.string :author_key, null: false
      t.jsonb :author, null: false, default: {}
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :last_status
      t.timestamps
    end
    add_index :inclamo_support_central_requests, [:source_id, :local_reference], unique: true, name: 'inclamo_support_request_identity'
    create_table :inclamo_support_receipts do |t|
      t.references :source, null: false, foreign_key: { to_table: :inclamo_support_sources, on_delete: :cascade }
      t.references :central_request, null: false, foreign_key: { to_table: :inclamo_support_central_requests, on_delete: :cascade }, index: { name: 'inclamo_receipt_request' }
      t.string :uuid, null: false
      t.string :digest, null: false
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :inclamo_support_receipts, [:source_id, :uuid], unique: true
    create_table :inclamo_support_uploads do |t|
      t.references :source, foreign_key: { to_table: :inclamo_support_sources, on_delete: :cascade }
      t.references :account_user, foreign_key: { on_delete: :cascade }
      t.string :reference, null: false, index: { unique: true }
      t.string :checksum, null: false
      t.bigint :submission_id
      t.bigint :receipt_id
      t.timestamps
    end
    create_table :inclamo_support_events do |t|
      t.references :source, null: false, foreign_key: { to_table: :inclamo_support_sources, on_delete: :cascade }
      t.references :central_request, null: false, foreign_key: { to_table: :inclamo_support_central_requests, on_delete: :cascade }, index: { name: 'inclamo_event_request' }
      t.string :identity, null: false
      t.jsonb :payload, null: false
      t.timestamps
    end
    add_index :inclamo_support_events, [:central_request_id, :identity], unique: true, name: 'inclamo_support_event_identity'
    create_table :inclamo_support_recipients do |t|
      t.references :source, null: false, foreign_key: { to_table: :inclamo_support_sources, on_delete: :cascade }
      t.string :account_key, null: false
      t.string :actor_key, null: false
      t.string :email, null: false
      t.boolean :active, null: false, default: true
      t.datetime :verified_at
      t.string :verification_digest
      t.datetime :verification_expires_at
      t.integer :verification_attempts, null: false, default: 0
      t.timestamps
    end
    add_index :inclamo_support_recipients, [:source_id, :account_key, :actor_key], unique: true, name: 'inclamo_support_recipient_identity'
    create_table :inclamo_support_deliveries do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :inclamo_support_recipients, on_delete: :cascade }
      t.references :central_request, null: false, foreign_key: { to_table: :inclamo_support_central_requests, on_delete: :cascade }, index: { name: 'inclamo_delivery_request' }
      t.bigint :message_id, null: false
      t.datetime :delivered_at
      t.datetime :next_attempt_at
      t.integer :attempts, null: false, default: 0
      t.timestamps
    end
    add_index :inclamo_support_deliveries, [:recipient_id, :message_id], unique: true
    create_table :inclamo_support_throttles do |t|
      t.string :key, null: false, index: { unique: true }
      t.integer :hits, null: false, default: 0
      t.datetime :expires_at, null: false
    end
  end
end
