# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The store app asks to let a Shopify staff member into the store's
    # account without a helpdesk password (docs/app-admin-entry.md). The app
    # says who the person is; this decides whether they get in and, if so,
    # makes the one-time address (EntryPass) that signs them in.
    #
    # Who gets in, in this order; the first failure ends it:
    #   1. the store has an account, else no_account (also while it is being
    #      erased: its row names no account then);
    #   2. the account is not suspended, else account_suspended;
    #   3. a user has the email and is a member of that account, else
    #      not_a_user: one answer for an unknown email and for a user of
    #      another account;
    #   4. the user has no second factor and none is required of them by an
    #      account they belong to, else two_factor: this way in does not ask
    #      for the code;
    #   5. Chatwoot would let the user sign in, a pending invitation aside,
    #      else not_a_user.
    # A user whose invitation is still pending is confirmed before the address
    # is made, as Chatwoot does after Google sign-in; no password is set.
    # Nothing is created: no user, no membership, no account.
    class Entry
      Result = Struct.new(:outcome, :status, :body, :user_id, keyword_init: true)

      # The refusals the app may show as they are (contract §3).
      REFUSALS = {
        not_a_user: [:forbidden, 'entry_not_a_user',
                     "This email is not a user of this helpdesk account. Ask the account's administrator to invite you."],
        two_factor: [:forbidden, 'entry_two_factor',
                     "Two-factor authentication is on for this user. Sign in on the helpdesk's login page with your password and code."],
        account_suspended: [:forbidden, 'entry_suspended', 'This helpdesk account is suspended.'],
        no_account: [:not_found, 'entry_no_account', nil]
      }.freeze

      def initialize(shop_domain, raw_body)
        @shop_domain = shop_domain
        @raw_body = raw_body
      end

      # Raises Payload::Invalid for a body that does not read.
      def call
        email = EntryPayload.new(@raw_body).email
        row = ProvisionedAccount.for_store(@shop_domain)
        account = row&.account
        return refusal(:no_account) unless account
        return refusal(:account_suspended) if !row.active? || account.suspended?

        user = User.from_email(email)
        return refusal(:not_a_user, user) unless user && AccountUser.exists?(account_id: account.id, user_id: user.id)
        return refusal(:two_factor, user) if user.mfa_enabled? || user.mfa_enforcement_pending?
        return refusal(:not_a_user, user) unless Entry.signs_in?(user)

        confirm(user)
        given(user, account)
      end

      # Whether Chatwoot lets the user sign in. A pending confirmation does
      # not count: this way in confirms it.
      def self.signs_in?(user)
        user.active_for_authentication? || user.inactive_message == :unconfirmed
      end

      private

      # As the Google callback does: the confirmation's time is set and saved,
      # and nothing else (no password, no letter).
      def confirm(user)
        return if user.confirmed?

        user.skip_confirmation!
        user.save!(validate: false)
      end

      def given(user, account)
        Result.new(outcome: 'entry_given', status: :ok, user_id: user.id,
                   body: { contract: CONTRACT, entry_url: EntryPass.issue(user, account), expires_in: EntryPass::LIFETIME })
      end

      def refusal(code, user = nil)
        status, outcome, message = REFUSALS.fetch(code)
        Result.new(outcome: outcome, status: status, user_id: user&.id, body: { error: code.to_s, message: message }.compact)
      end
    end
  end
end
