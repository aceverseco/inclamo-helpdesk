# frozen_string_literal: true

# Accounts that existed before team queues get the ready queues and replies.
# Each account is installed on its own, outside one wrapping transaction, so
# what succeeded stays. When an account could not be served the migration
# fails, naming the accounts, and is not recorded as run: the next
# `inclamo:db:migrate` installs again, which changes nothing where the
# installation is complete. Inclamo::PresetsRepairJob repairs the same
# accounts in the running application meanwhile.
class InstallInclamoReadyPresets < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    failed = []
    Account.find_each do |account|
      Account.transaction(requires_new: true) { Inclamo::Presets.install!(account) }
    rescue StandardError => e
      failed << account.id
      say "account #{account.id}: #{e.class.name}: #{e.message}"
    end
    raise "the ready team queues and replies were not installed for accounts #{failed.join(', ')}; run the migration again" if failed.any?
  end

  def down; end
end
