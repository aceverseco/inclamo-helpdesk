# frozen_string_literal: true

module Inclamo
  # Installs the ready material of an account: team queues with their labels,
  # and saved replies. Safe to run any number of times.
  #
  # Three callers. A new account's own hook (Custom::Concerns::Account) uses
  # `install`, which never fails the account's creation. The migration for
  # accounts older than this uses `install!` and fails when an account could
  # not be served. And Inclamo::PresetsRepairJob runs `repair` every few
  # minutes: it finds the accounts still lacking something and installs again,
  # so a failure of either of the first two is made good without a deploy.
  module Presets
    INSTALLERS = [TeamQueues::Installer, ReadyReplies].freeze
    # Accounts one repair run serves at most; the next run goes on.
    REPAIR_BATCH = 200

    # Accounts that lack a ready queue, or a ready reply never offered to them.
    INCOMPLETE = <<~SQL.squish.freeze
      (SELECT COUNT(*) FROM inclamo_team_queues queues WHERE queues.account_id = accounts.id AND queues.key IN (:queues)) < :queue_count
      OR (SELECT COUNT(*) FROM inclamo_preset_installs installs
          WHERE installs.account_id = accounts.id AND installs.kind = :kind AND installs.key IN (:replies)) < :reply_count
    SQL

    module_function

    # Every installer runs even when an earlier one failed; the first failure is raised.
    def install!(account)
      failures = INSTALLERS.filter_map do |installer|
        installer.call(account)
        nil
      rescue StandardError => e
        e
      end
      raise failures.first if failures.any?
    end

    # The same, reported instead of raised. Answers whether everything was installed.
    def install(account)
      install!(account)
      true
    rescue StandardError => e
      Rails.logger.error("[inclamo] ready presets not installed for account #{account.id}: #{e.class.name}: #{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
      false
    end

    def incomplete
      Account.where(INCOMPLETE, queues: TeamQueues::READY.keys, queue_count: TeamQueues::READY.size, kind: ReadyReplies::KIND,
                                replies: ReadyReplies::READY.keys, reply_count: ReadyReplies::READY.size)
    end

    # Installs for up to `limit` incomplete accounts, oldest first. A failing
    # account is reported and does not stop the others. Answers the ids it
    # could not serve.
    def repair(limit: REPAIR_BATCH)
      incomplete.order(:id).limit(limit).reject { |account| install(account) }.map(&:id)
    end
  end
end
