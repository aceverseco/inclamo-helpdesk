# frozen_string_literal: true

module Inclamo
  module Erasure
    # Finding one shopper in a store's account (docs/app-store-erasure.md
    # §4.2): the account's contacts whose email equals the given one without
    # regard to letter case, and those whose phone has the same digits as the
    # given one (the form in which Shopify sends a phone is not known, so only
    # the digits are compared). Nothing else is searched: a conversation the
    # same person started under another email, or on a channel without an
    # email or a phone, is not found. The tickets' own contact is never a
    # shopper.
    #
    # A request's email and phone are kept readable only while its ticket is
    # open; afterwards only their keyed digests are (`digest`), which is also
    # how a repeated request finds the earlier one.
    module Shoppers
      DIGEST_PURPOSE = 'inclamo erasure shopper digest'
      # An erasure or a data request still unmet this long after it was
      # received counts as overdue (the app's counts).
      OVERDUE_AFTER = 30.days

      module_function

      # The email as it is compared: without surrounding blanks, in lower case.
      def email(text)
        text.to_s.strip.downcase.presence
      end

      # The phone as it is compared: its digits only.
      def digits(text)
        text.to_s.gsub(/\D/, '').presence
      end

      # HMAC-SHA256 under a key derived from the installation's secret key base.
      def digest(value)
        return if value.blank?

        OpenSSL::HMAC.hexdigest('SHA256', key, value)
      end

      def key
        Rails.application.key_generator.generate_key(DIGEST_PURPOSE, 32)
      end

      # The account's contacts that match the email or the phone.
      def matching(account, email:, phone:)
        email = self.email(email)
        digits = self.digits(phone)
        return Contact.none unless account && (email || digits)

        conditions = []
        conditions << 'LOWER(contacts.email) = :email' if email
        conditions << "regexp_replace(COALESCE(contacts.phone_number, ''), '[^0-9]', '', 'g') = :digits" if digits
        own = Inclamo::DataRequestInbox.where(account_id: account.id).where.not(contact_id: nil).select(:contact_id)
        Contact.where(account_id: account.id).where("(#{conditions.join(' OR ')})", email: email, digits: digits).where.not(id: own)
      end

      # How many conversations the contacts have.
      def conversation_count(contacts)
        Conversation.where(contact_id: contacts.map(&:id)).count
      end

      # A request about a shopper that is not done and was received more than
      # OVERDUE_AFTER ago.
      def overdue?(request, now = Time.current)
        !request.done? && request.received_at <= now - OVERDUE_AFTER
      end
    end
  end
end
