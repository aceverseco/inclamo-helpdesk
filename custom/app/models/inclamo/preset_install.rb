# frozen_string_literal: true

# One ready item the installer has offered an account (see Inclamo::ReadyReplies).
class Inclamo::PresetInstall < ApplicationRecord
  belongs_to :account
end
