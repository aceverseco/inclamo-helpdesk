# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The body of "let this staff member in" (docs/app-admin-entry.md §1):
    #   { "contract": 1, "staff": { "email": "...", "email_verified": true } }
    # A body that does not read raises Payload::Invalid with the contract's
    # error code; the message is English text for a developer's log.
    class EntryPayload
      MAX_EMAIL = 255

      attr_reader :email

      def initialize(raw_body)
        body = parse(raw_body)
        invalid!('contract_unsupported', "contract must be #{CONTRACT}") unless body['contract'] == CONTRACT

        staff = body['staff'].is_a?(Hash) ? body['staff'] : {}
        @email = EntryPayload.email(staff['email']) || invalid!('staff_email_missing', 'staff.email is absent or does not read as an email')
        invalid!('staff_email_unverified', 'staff.email_verified must be true') unless staff['email_verified'] == true
      end

      # The email as the helpdesk compares it, or nil when the value does not
      # read as one. The request limits read it the same way.
      def self.email(value)
        email = value.is_a?(String) ? value.strip.downcase : ''
        email if email.length <= MAX_EMAIL && Devise.email_regexp.match?(email)
      end

      private

      # A body that is not a JSON object states no contract version at all.
      def parse(raw_body)
        body = JSON.parse(raw_body.to_s)
        body.is_a?(Hash) ? body : invalid!('contract_unsupported', 'the body is not a JSON object')
      rescue JSON::ParserError
        invalid!('contract_unsupported', 'the body is not a JSON object')
      end

      def invalid!(code, message)
        raise Payload::Invalid.new(code, message)
      end
    end
  end
end
