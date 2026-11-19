# frozen_string_literal: true

module Inclamo
  # Shopify's compliance requests for data kept in the hosted helpdesk
  # (capability app-store-erasure, contract in docs/app-store-erasure.md),
  # passed on by the store app over the provisioning channel.
  #
  # A store's erasure is scheduled for the end of the installation's waiting
  # time (Schedule), withdrawn when the store installs the app again in time
  # (Erasure.cancel!), started by the daily run (Inclamo::ErasureCheckJob) and
  # carried out by Store: the account is destroyed with everything in it, and
  # the store's row keeps only its domain, the fact and the time. Each
  # completed erasure is also written to a journal outside the database
  # (Journal), so that it can be applied again after a restore (Reapply).
  module Erasure
    # The waiting time of a store's erasure, in days: an operator setting with
    # this default and this range. A value outside it falls back to the default.
    STORE_WAIT_DAYS = 7
    STORE_WAIT_RANGE = (0..21)
    # Due erasures are looked for once a day.
    CHECK_CRON = '10 4 * * *'

    class << self
      # The waiting time of a store's erasure, counted from the first accepted
      # request. The end-to-end stack counts it in seconds.
      def store_wait
        seconds = e2e_seconds('INCLAMO_ERASURE_WAIT_SECONDS')
        return seconds.seconds if seconds

        days = whole(ENV.fetch('INCLAMO_ERASURE_WAIT_DAYS', nil))
        (days && STORE_WAIT_RANGE.cover?(days) ? days : STORE_WAIT_DAYS).days
      end

      # When the daily run comes: once a day, or in the end-to-end stack every
      # few seconds (a cron line of Inclamo::Sla's form).
      def check_cron
        seconds = check_seconds
        seconds ? Inclamo::Sla.check_cron(seconds) : CHECK_CRON
      end

      def check_seconds
        seconds = e2e_seconds('INCLAMO_ERASURE_CHECK_SECONDS')
        Inclamo::Sla.even_interval(seconds) if seconds&.positive?
      end

      # Where completed erasures are journaled; nil when the operator set no place.
      def journal_path
        ENV.fetch('INCLAMO_ERASURE_JOURNAL_PATH', '').strip.presence
      end

      # The store's scheduled erasure is withdrawn: the store installed the app
      # again before its time. Called under the store's row lock, by the
      # restoration of the account. True when there was one to withdraw.
      def cancel!(row, now: Time.current)
        record = Inclamo::ErasureRequest.scheduled_store(row.shop_domain)
        scheduled = row.erase_after.present? || record.present?
        row.update!(erase_after: nil) if row.erase_after
        record&.update!(state: 'cancelled', completed_at: now)
        scheduled
      end

      private

      def whole(text)
        Integer(text.to_s.strip, 10, exception: false)
      end

      # Settings of the end-to-end stack only (INCLAMO_E2E=1), like the
      # Shopify proxy's address: a real installation never counts in seconds.
      def e2e_seconds(name)
        return unless ENV['INCLAMO_E2E'] == '1'

        value = whole(ENV.fetch(name, nil))
        value if value && value >= 0
      end
    end
  end
end
