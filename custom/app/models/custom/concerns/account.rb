# frozen_string_literal: true

# A new account gets the ready team queues and saved replies (capabilities
# team-queues and ready-replies). Accounts older than these were given them by
# a migration.
#
# Included through Chatwoot's extension hook,
# `Account.include_mod_with('Concerns::Account')` (app/models/account.rb:250).
module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    after_create_commit :inclamo_install_ready_presets
  end

  private

  def inclamo_install_ready_presets
    Inclamo::Presets.install(self)
  end
end
