# frozen_string_literal: true

# The key of a call filed by the AI service (Inclamo::Ai::Calls::File): which
# conversation holds the call with this id in the account. The call itself is
# an ordinary conversation of the Phone inbox.
class Inclamo::CallConversation < ApplicationRecord
  MATCHES = %w[phone email created anonymous ambiguous].freeze

  belongs_to :account
  belongs_to :conversation, optional: true

  validates :call_id, presence: true
  validates :matched_by, inclusion: { in: MATCHES }, allow_nil: true
end
