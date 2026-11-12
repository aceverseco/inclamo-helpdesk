# frozen_string_literal: true

class Inclamo::Support::NotificationPreference < ApplicationRecord
  self.table_name = 'inclamo_support_notification_preferences'
  belongs_to :account_user

  def self.enabled_for?(member)
    return false unless member

    find_by(account_user_id: member.id)&.enabled != false
  end
end
