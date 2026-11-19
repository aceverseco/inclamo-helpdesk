# frozen_string_literal: true

module Inclamo
  module Erasure
    # Every column of the overlay's tables that names an account, a contact, a
    # conversation or a Shopify order, with what the database does to the row
    # when the record it names is destroyed:
    #   :cascade   the row goes with it (a foreign key ON DELETE CASCADE);
    #   :nullify   the column is emptied (ON DELETE SET NULL);
    #   :restrict  the record cannot be destroyed while the row is there (a
    #              foreign key without an action): an erasure removes the row first;
    #   :none      no foreign key: the row stays and names something that may
    #              be gone (a Shopify order is never a row of this database).
    # A table added to the overlay with such a column must be listed here, with
    # a decision about how an erasure reaches it; the spec of this list fails
    # until it is (custom/spec/lib/inclamo/erasure/references_spec.rb).
    module References
      COLUMN = /\A(?:(?:account|contact|contact_inbox|conversation|order|customer)_id|order_number|order_ids)\z/

      LIST = {
        'inclamo_ai_connections' => { 'account_id' => :cascade },
        'inclamo_ai_identity_verifications' => { 'account_id' => :restrict, 'contact_inbox_id' => :restrict, 'customer_id' => :none },
        'inclamo_ai_policies' => { 'account_id' => :restrict },
        'inclamo_ai_proposals' => { 'account_id' => :restrict, 'conversation_id' => :restrict },
        'inclamo_call_conversations' => { 'account_id' => :cascade, 'conversation_id' => :cascade, 'contact_id' => :none },
        'inclamo_discount_presets' => { 'account_id' => :cascade },
        # The erasures' own record: it outlives what it names (KEPT).
        'inclamo_erasure_requests' => { 'account_id' => :none, 'conversation_id' => :none, 'order_ids' => :none },
        'inclamo_order_actions' => {
          'account_id' => :cascade, 'conversation_id' => :nullify, 'order_id' => :none, 'order_number' => :none, 'customer_id' => :none
        },
        'inclamo_preset_installs' => { 'account_id' => :cascade },
        # The store's row names no account from the start of its erasure on.
        'inclamo_provisioned_accounts' => { 'account_id' => :cascade },
        # The record of the store app's attempts keeps the attempt, not the account.
        'inclamo_provisioning_events' => { 'account_id' => :nullify },
        'inclamo_setup_states' => { 'account_id' => :restrict },
        'inclamo_shopify_connections' => { 'account_id' => :cascade },
        'inclamo_sla_policies' => { 'account_id' => :cascade },
        'inclamo_sla_timers' => { 'conversation_id' => :cascade },
        'inclamo_support_central_requests' => { 'conversation_id' => :cascade },
        'inclamo_support_requests' => { 'account_id' => :cascade },
        'inclamo_team_queues' => { 'account_id' => :cascade },
        'inclamo_website_widgets' => { 'account_id' => :cascade },
        'inclamo_workspace_defaults' => { 'account_id' => :cascade }
      }.freeze

      # Tables that keep naming what was erased, by design.
      KEPT = %w[inclamo_erasure_requests].freeze

      # Tables of Chatwoot with an account's rows that nothing of Chatwoot's
      # removes with the account: its reports' daily totals, written for an
      # account with a reporting time zone.
      CHATWOOT_UNREACHED = %w[reporting_events_rollups].freeze

      module_function

      # [table, column] of the overlay's tables, as the database has them.
      def found
        connection.select_rows(<<~SQL.squish).select { |_table, column| COLUMN.match?(column) }
          SELECT columns.table_name, columns.column_name FROM information_schema.columns
          JOIN information_schema.tables ON tables.table_schema = columns.table_schema AND tables.table_name = columns.table_name
          WHERE columns.table_schema = current_schema() AND tables.table_type = 'BASE TABLE' AND columns.table_name LIKE 'inclamo\\_%'
        SQL
      end

      # Columns the database has and the list does not, and the other way round.
      def unlisted
        found - listed
      end

      def stale
        listed - found
      end

      def listed
        LIST.flat_map { |table, columns| columns.keys.map { |column| [table, column] } }
      end

      # [table, column, listed, actual] where the list says another thing than
      # the database's foreign key does.
      def mismatched
        LIST.flat_map do |table, columns|
          keys = connection.table_exists?(table) ? connection.foreign_keys(table) : []
          columns.filter_map do |column, listed|
            key = keys.find { |one| one.column == column }
            actual = key ? (key.on_delete || :restrict) : :none
            [table, column, listed, actual] unless actual == listed
          end
        end
      end

      # The overlay's tables whose rows hold an account back: an erasure
      # deletes their rows of the account before the account itself.
      def holding_account
        LIST.select { |table, columns| columns['account_id'] == :restrict && KEPT.exclude?(table) }.keys
      end

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end
