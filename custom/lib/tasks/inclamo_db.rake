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

# Chatwoot's own `db:migrate` (also the last step of `db:chatwoot_prepare`)
# brings the overlay's tables up to date as well.
Rake::Task['db:migrate'].enhance do
  Rake::Task['inclamo:db:migrate'].invoke
end
