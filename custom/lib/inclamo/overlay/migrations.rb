# frozen_string_literal: true

module Inclamo
  module Overlay
    # Runs the overlay's migrations from custom/db/migrate and records them in
    # a table of their own.
    #
    # They are kept apart from Chatwoot's migrations on purpose. A fresh install
    # loads Chatwoot's schema.rb, and Rails then marks every known migration
    # older than that schema as already run. With a shared record, an overlay
    # migration older than the next Chatwoot release would be marked as run
    # without its table ever being created.
    module Migrations
      PATH = Overlay::ROOT.join('db/migrate').to_s
      TABLE = 'inclamo_schema_migrations'

      # Same behaviour as Rails' own record of migrations, under another name.
      class Record < ActiveRecord::SchemaMigration
        def table_name
          TABLE
        end
      end

      class << self
        def migrate(target_version = nil)
          context.migrate(target_version)
        end

        def rollback(steps = 1)
          context.rollback(steps)
        end

        def pending?
          context.needs_migration?
        end

        def status
          applied = record.table_exists? ? record.integer_versions : []
          context.migrations.map { |migration| [migration.version, migration.name, applied.include?(migration.version)] }
        end

        private

        def context
          ActiveRecord::MigrationContext.new([PATH], record, ActiveRecord::InternalMetadata.new(pool))
        end

        def record
          Record.new(pool)
        end

        def pool
          ActiveRecord::Base.connection_pool
        end
      end
    end
  end
end
