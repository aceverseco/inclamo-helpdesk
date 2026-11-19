# frozen_string_literal: true

module Inclamo
  module Ai
    # Why connecting or disconnecting did not happen. `code` is what the API
    # answers; the dashboard words each code itself.
    class Error < StandardError
      def code
        self.class.name.demodulize.underscore
      end

      # The code does not decode, lacks a field, or names an address other than HTTPS.
      class InvalidCode < Error; end

      # The AI service answered 4xx; the message is its own words.
      class Refused < Error
        attr_reader :service_error

        def initialize(message, service_error: nil)
          @service_error = service_error
          super(message)
        end
      end

      # No answer, an answer of another kind, or no answer in time. A malformed
      # 201 may still carry the AI service's id, to remove what it made.
      class NotAnswered < Error
        attr_reader :connection_id

        def initialize(message = nil, connection_id: nil)
          @connection_id = connection_id
          super(message)
        end
      end

      class NoInboxes < Error; end
      # Not an inbox of the account, or the Phone inbox.
      class InvalidInbox < Error; end
      # A chosen inbox already has another bot or Dialogflow.
      class InboxHasBot < Error; end
      class AlreadyConnected < Error; end
      class NotConnected < Error; end
      # Another connection, disconnection or change of the inboxes of the
      # account is under way.
      class Busy < Error; end
      class EncryptionNotConfigured < Error; end
      # The AI service has no call to change the inboxes: it answered 404, 405
      # or 501 (docs/ai-connector.md §1.4).
      class ChangeUnsupported < Error; end
      # The AI service accepted a change of the inboxes the helpdesk then could
      # not apply; the earlier inboxes stay (Inclamo::Ai::ChangeInboxes).
      class NotApplied < Error; end
    end
  end
end
