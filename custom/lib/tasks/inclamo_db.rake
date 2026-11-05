# frozen_string_literal: true

namespace :inclamo do
  namespace :db do
    desc 'Run the migrations of the Inclamo Helpdesk overlay'
    task migrate: :environment do
      Inclamo::Overlay::Migrations.migrate(ENV['VERSION']&.to_i)
    end

    desc 'Roll back the last migration of the overlay (STEP=n for more)'
    task rollback: :environment do
      Inclamo::Overlay::Migrations.rollback(ENV.fetch('STEP', 1).to_i)
    end

    desc 'List the migrations of the overlay and whether each has run'
    task status: :environment do
      Inclamo::Overlay::Migrations.status.each do |version, name, applied|
        puts format('%<state>-5s %<version>d  %<name>s', state: applied ? 'up' : 'down', version: version, name: name)
      end
    end
  end
end

# Every way Chatwoot brings its database up to date brings the overlay's tables
# up to date as well:
# - `db:migrate`;
# - `db:chatwoot_prepare`, the command of a Chatwoot installation: on a server
#   without a database it runs `db:setup` and never reaches `db:migrate`;
# - `db:setup` and `db:prepare`, for the same reason;
# - `db:test:prepare`: the test helper of Chatwoot rebuilds the test database
#   from schema.rb whenever that file changed, and schema.rb does not hold the
#   overlay's tables.
# Running the overlay's migrations twice is harmless: the second run finds
# nothing to do.
%w[db:migrate db:chatwoot_prepare db:setup db:prepare db:test:prepare].each do |name|
  next unless Rake::Task.task_defined?(name)

  Rake::Task[name].enhance do
    Rake::Task['inclamo:db:migrate'].reenable
    Rake::Task['inclamo:db:migrate'].invoke
  end
end
