# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'
require 'sidekiq/api'

module Inclamo
  # What GET /inclamo/health answers from (Inclamo::HealthController). Each
  # check is good or failing; a check that raises is failing. Nothing here
  # returns a count, a setting or anything of a merchant's.
  module Health
    CHECKS = %i[database redis workers backup restore_test disk].freeze

    # Written by the backup and restore-test scripts on the host and mounted
    # read-only into the container:
    #   { "last_backup_at": "<ISO 8601>", "last_restore_test_at": "<ISO 8601>" }
    # (seconds since the epoch are read too; other keys are ignored).
    STATUS_FILE = '/var/lib/inclamo-helpdesk/backup-status.json'
    BACKUP_MAX_AGE = 26.hours.to_i
    RESTORE_TEST_MAX_AGE = 35.days.to_i
    # Sidekiq beats every 10 seconds and its record expires after 60.
    WORKER_BEAT_MAX_AGE = 60
    DISK_MIN_FREE = 0.15
    # The container's own root lies on Docker's data filesystem, where named
    # volumes (the database's among them) are kept by default. With the
    # database on another disk, mount a directory of that disk into the
    # container and name it in INCLAMO_HEALTH_DISK_PATH.
    DISK_PATH = '/'

    class << self
      # Names of the failing checks, in the order of CHECKS.
      def failing
        CHECKS.reject { |name| passes?(name) }.map(&:to_s)
      end

      def passes?(name)
        send(:"#{name}_ok?") ? true : false
      rescue StandardError => e
        # The class only: a message may carry an address or a credential.
        Rails.logger.warn("inclamo health: #{name} check raised #{e.class}")
        false
      end

      def database_ok?
        query_database.to_i == 1
      end

      def redis_ok?
        ping_redis == 'PONG'
      end

      def workers_ok?
        newest = worker_beats.max
        !newest.nil? && Time.current.to_f - newest < WORKER_BEAT_MAX_AGE
      end

      def backup_ok?
        fresh?('last_backup_at', BACKUP_MAX_AGE)
      end

      def restore_test_ok?
        fresh?('last_restore_test_at', RESTORE_TEST_MAX_AGE)
      end

      def disk_ok?
        disk_free_ratio(disk_path) > DISK_MIN_FREE
      end

      # A real query: `connection.active?` is false on a connection that has
      # not been used yet.
      def query_database
        ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value('SELECT 1') }
      end

      def ping_redis
        redis = Redis.new(Redis::Config.app)
        redis.ping
      ensure
        redis&.close
      end

      # The last beat of every Sidekiq process in its registry, read only.
      def worker_beats
        Sidekiq::ProcessSet.new(false).map { |process| process['beat'].to_f }
      end

      def status_file
        ENV.fetch('INCLAMO_BACKUP_STATUS_FILE', nil).presence || STATUS_FILE
      end

      def disk_path
        ENV.fetch('INCLAMO_HEALTH_DISK_PATH', nil).presence || DISK_PATH
      end

      # Share of the filesystem holding `path` that is still free to write, as
      # `df` counts it (available / (used + available)).
      def disk_free_ratio(path)
        output, _errors, status = Open3.capture3('df', '-Pk', path.to_s)
        raise "df exited with #{status.exitstatus}" unless status.success?

        figures = output.lines.last.to_s.match(/\s(\d+)\s+(\d+)\s+(\d+)\s+\d+%/)
        raise 'df answered in an unknown form' unless figures

        used = figures[2].to_f
        available = figures[3].to_f
        raise 'df reported an empty filesystem' unless (used + available).positive?

        available / (used + available)
      end

      private

      def fresh?(key, max_age)
        at = recorded_time(recorded[key])
        !at.nil? && Time.current.to_f - at.to_f < max_age
      end

      def recorded
        parsed = JSON.parse(File.read(status_file))
        parsed.is_a?(Hash) ? parsed : {}
      end

      def recorded_time(value)
        case value
        when Numeric then Time.zone.at(value)
        when String then Time.iso8601(value)
        end
      end
    end
  end
end
