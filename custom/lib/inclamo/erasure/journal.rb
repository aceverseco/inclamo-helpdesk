# frozen_string_literal: true

module Inclamo
  module Erasure
    # The journal of completed erasures: one JSON line per erasure, appended to
    # a file outside the database (INCLAMO_ERASURE_JOURNAL_PATH). A backup of
    # the database taken before an erasure does not hold its completion; after
    # that backup is restored, the journal says what to erase again (Reapply).
    # A line names the store, the account and the times; never a person's
    # email, phone or name.
    module Journal
      class Unwritable < StandardError; end

      module_function

      # Appends the line. Without a configured place nothing is written and the
      # operator is warned; a place that cannot be written raises Unwritable.
      def append(entry, path: Erasure.journal_path)
        unless path
          Rails.logger.warn('[inclamo erasure] no journal configured (INCLAMO_ERASURE_JOURNAL_PATH): ' \
                            'this erasure cannot be applied again after a restore')
          return false
        end

        File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          file.write("#{entry.to_json}\n")
          file.flush
          file.fsync
        end
        true
      rescue SystemCallError, IOError => e
        raise Unwritable, "the erasure journal cannot be written: #{e.class}"
      end

      # The line of a store's completed erasure.
      def store_entry(record)
        {
          kind: 'store', shop_domain: record.shop_domain, account_id: record.account_id,
          received_at: record.received_at&.utc&.iso8601, completed_at: record.completed_at&.utc&.iso8601
        }
      end

      # The lines of the journal at `path`, oldest first. A line that does not
      # read is skipped with a warning.
      def read(path)
        File.foreach(path).with_index(1).filter_map do |line, number|
          next if line.strip.empty?

          entry = JSON.parse(line)
          next entry if entry.is_a?(Hash)

          Rails.logger.warn("[inclamo erasure] journal line #{number} is not an object; skipped")
          nil
        rescue JSON::ParserError
          Rails.logger.warn("[inclamo erasure] journal line #{number} does not read; skipped")
          nil
        end
      end
    end
  end
end
