# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Overlay::Migrations do
  let(:connection) { ActiveRecord::Base.connection }
  let(:dir) { Dir.mktmpdir('inclamo-migrations') }
  # Older than every migration of Chatwoot: the case a shared record would lose.
  let(:version) { 20_200_101_000_000 }

  before do
    File.write(File.join(dir, "#{version}_create_inclamo_spec_probe.rb"), <<~RUBY)
      class CreateInclamoSpecProbe < ActiveRecord::Migration[7.1]
        def change
          create_table :inclamo_spec_probe do |t|
            t.string :note
          end
        end
      end
    RUBY
    stub_const("#{described_class}::PATH", dir)
  end

  after { FileUtils.remove_entry(dir) }

  def quietly(&)
    ActiveRecord::Migration.suppress_messages(&)
  end

  it 'runs a migration and records it apart from the migrations of Chatwoot' do
    expect(described_class.pending?).to be(true)

    quietly { described_class.migrate }

    expect(connection.table_exists?(:inclamo_spec_probe)).to be(true)
    expect(described_class.pending?).to be(false)
    expect(described_class.status).to include([version, 'CreateInclamoSpecProbe', true])
    expect(connection.select_values("SELECT version FROM #{described_class::TABLE}")).to include(version.to_s)
    expect(connection.select_values('SELECT version FROM schema_migrations')).not_to include(version.to_s)
  end

  it 'is not marked as run when the schema of Chatwoot is assumed up to date' do
    connection.assume_migrated_upto_version(ActiveRecord::Migrator.current_version)

    expect(described_class.pending?).to be(true)
  end

  context 'when it is the newest migration' do
    # Rolling back takes the newest recorded migration, so the probe must be
    # newer than the overlay's real ones.
    let(:version) { 20_990_101_000_000 }

    it 'rolls it back' do
      quietly do
        described_class.migrate
        described_class.rollback
      end

      expect(connection.table_exists?(:inclamo_spec_probe)).to be(false)
      expect(described_class.pending?).to be(true)
    end
  end

  it 'follows every task with which Chatwoot prepares its database, a first installation included' do
    %w[db:migrate db:chatwoot_prepare db:setup db:prepare db:test:prepare].each do |name|
      actions = Rake::Task[name].actions.map { |action| action.source_location.first }

      expect(actions).to include(a_string_ending_with('custom/lib/tasks/inclamo_db.rake')), "#{name} does not run the overlay's migrations"
    end
  end

  it 'keeps its tables out of the schema dump of Chatwoot' do
    expect(ActiveRecord::SchemaDumper.ignore_tables).to include(/\Ainclamo_/)
  end
end
