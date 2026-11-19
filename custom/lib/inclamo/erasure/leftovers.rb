# frozen_string_literal: true

module Inclamo
  module Erasure
    # What is left of an erased account or of its deleted users: the tables of
    # the database (Chatwoot's and the overlay's) that still hold a row naming
    # them. The tables are read from the schema at each look, not from a list
    # kept by hand, so a table added later is looked at too: every table with
    # a whole-number account_id (or user_id) column. Only the erasures' own
    # record (References::KEPT) may keep naming them.
    module Leftovers
      module_function

      # The tables with a row whose account_id is the account's, and `accounts`
      # itself while the account is there.
      def account(account_id)
        tables = holding(tables_with('account_id'), 'account_id', [account_id])
        Account.exists?(id: account_id) ? ['accounts', *tables] : tables
      end

      # The tables with a row whose user_id is one of the users', and `users`
      # while one of them is there.
      def users(user_ids)
        ids = Array(user_ids).compact
        return [] if ids.empty?

        tables = holding(tables_with('user_id'), 'user_id', ids)
        User.exists?(id: ids) ? ['users', *tables] : tables
      end

      def tables_with(column)
        connection.select_values(<<~SQL.squish) - References::KEPT
          SELECT columns.table_name FROM information_schema.columns
          JOIN information_schema.tables ON tables.table_schema = columns.table_schema AND tables.table_name = columns.table_name
          WHERE columns.table_schema = current_schema() AND tables.table_type = 'BASE TABLE'
            AND columns.column_name = #{connection.quote(column)} AND columns.data_type IN ('integer', 'bigint')
          ORDER BY columns.table_name
        SQL
      end

      def holding(tables, column, ids)
        list = ids.map { |id| connection.quote(Integer(id)) }.join(', ')
        tables.select do |table|
          connection.select_value(
            "SELECT 1 FROM #{connection.quote_table_name(table)} WHERE #{connection.quote_column_name(column)} IN (#{list}) LIMIT 1"
          ).present?
        end
      end

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end
