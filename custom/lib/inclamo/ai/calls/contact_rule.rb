# frozen_string_literal: true

module Inclamo
  module Ai
    module Calls
      # Which contact a call goes to. First match wins: the one contact with
      # the caller's number, then the one contact with the email the AI service
      # sent, otherwise a new contact. Two or more contacts at a step: none is
      # picked and the new contact is marked as ambiguous. A contact that
      # existed is never changed.
      class ContactRule
        Result = Struct.new(:contact, :matched_by, keyword_init: true)

        def initialize(account, filing)
          @account = account
          @filing = filing
        end

        def call
          found, how = match
          return Result.new(contact: found, matched_by: how) if found

          Result.new(contact: create, matched_by: how)
        end

        private

        # [contact or nil, how]
        def match
          return [nil, 'anonymous'] if @filing.phone.blank? && @filing.email.blank?

          [[with_phone, 'phone'], [with_email, 'email']].each do |contacts, how|
            return [contacts.first, how] if contacts.size == 1
            return [nil, 'ambiguous'] if contacts.size > 1
          end
          [nil, 'created']
        end

        def with_phone
          return [] if @filing.phone.blank?

          @account.contacts.where(phone_number: @filing.phone).limit(2).to_a
        end

        def with_email
          return [] if @filing.email.blank?

          @account.contacts.where('LOWER(email) = ?', @filing.email.downcase).limit(2).to_a
        end

        # Chatwoot lets one contact of an account hold a number or an email
        # (app/models/contact.rb), so a new contact carries neither when
        # another contact has it already: the call's card still shows the number.
        def create
          @account.contacts.create!(
            name: @filing.name || placeholder_name,
            phone_number: free?(:phone_number, @filing.phone) ? @filing.phone : nil,
            email: free_email? ? @filing.email : nil,
            identifier: free?(:identifier, identifier) ? identifier : nil
          )
        end

        def identifier
          "inclamo:customer:#{@filing.call_id}"
        end

        def placeholder_name
          I18n.t(@filing.entry == 'web' ? 'inclamo.ai_calls.website_visitor' : 'inclamo.ai_calls.unknown_caller')
        end

        def free?(column, value)
          value.present? && !@account.contacts.exists?(column => value)
        end

        def free_email?
          @filing.email.present? && !@account.contacts.exists?(['LOWER(email) = ?', @filing.email.downcase])
        end
      end
    end
  end
end
