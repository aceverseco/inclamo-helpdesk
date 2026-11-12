# frozen_string_literal: true

module Inclamo
  # Installs the ready material of an account: team queues with their labels,
  # and saved replies. Safe to run any number of times. It never fails its
  # caller: an account is created, and a migration goes on, whatever happens
  # here; what failed is reported and installed by the next run.
  module Presets
    module_function

    def install(account)
      [TeamQueues::Installer, ReadyReplies].each do |installer|
        installer.call(account)
      rescue StandardError => e
        Rails.logger.error("[inclamo] ready presets not installed for account #{account.id}: #{e.class.name}: #{e.message}")
        ChatwootExceptionTracker.new(e, account: account).capture_exception
      end
    end
  end
end
