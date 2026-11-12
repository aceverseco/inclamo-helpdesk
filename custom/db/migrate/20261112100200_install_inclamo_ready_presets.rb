# frozen_string_literal: true

# Accounts that existed before team queues get the ready queues and replies.
# An account that fails is reported and left for the next installation.
class InstallInclamoReadyPresets < ActiveRecord::Migration[7.1]
  def up
    Account.find_each { |account| Inclamo::Presets.install(account) }
  end

  def down; end
end
