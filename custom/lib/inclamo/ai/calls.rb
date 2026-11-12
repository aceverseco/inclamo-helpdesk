# frozen_string_literal: true

module Inclamo
  module Ai
    # A finished call of the AI phone agent, filed as a conversation of the
    # account's Phone inbox. The contract with the AI service is
    # docs/ai-connector-calls.md.
    module Calls
      ENTRIES = %w[inbound outbound web].freeze
      PRIORITIES = %w[low medium high urgent].freeze
      ROLES = %w[caller agent].freeze

      CALL_ID_FORMAT = /\A[A-Za-z0-9_:.\-]{1,100}\z/
      E164 = /\A\+[1-9]\d{1,14}\z/
      OUTCOME_FORMAT = /\A[a-z0-9_]{1,50}\z/
      # Narrower than the agent's labels on a chat: no hyphen.
      LABEL_FORMAT = /\Ainclamo_[a-z0-9_]+\z/

      MAX_LABELS = 20
      MAX_TURNS = 500
      MAX_TURN_LENGTH = 10_000
      MAX_RECORD_LENGTH = 8_000
      MAX_NAME_LENGTH = 255
      MAX_URL_LENGTH = 2_000

      AMBIGUOUS_LABEL = 'inclamo_match_ambiguous'
      NO_CALLER_ID_LABEL = 'inclamo_no_caller_id'

      # A filing the helpdesk refuses. `code` is one of the contract's codes;
      # the message never holds a part of the call.
      class Refused < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code.to_s)
        end
      end
    end
  end
end
