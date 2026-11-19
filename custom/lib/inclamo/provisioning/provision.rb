# frozen_string_literal: true

module Inclamo
  module Provisioning
    # "The store has an account": creates the store's account with the named
    # person as administrator, finds the one it has, or restores a suspended
    # one. Safe to repeat and safe to run twice at once. The app's address for
    # the store's key requests, when the request gives one, is kept on the
    # store's row in each case.
    class Provision
      # `admin_is_member`: whether the named person is a user of the account
      # once the request is done.
      Result = Struct.new(:row, :account, :outcome, :admin_is_member, :password_setup_url, keyword_init: true)

      ATTEMPTS = 3

      def initialize(payload)
        @payload = payload
      end

      def call
        attempts = 0
        begin
          attempts += 1
          row = ProvisionedAccount.for_store(@payload.shop_domain)
          row ? existing(row) : create
        rescue ActiveRecord::RecordNotUnique
          # Another request made the row (or the user) first: it has committed
          # by the time the unique index refuses us, so read what it made.
          retry if attempts < ATTEMPTS
          raise
        end
      end

      private

      # The row goes in first. A second request for the same new store waits on
      # the unique index until this transaction ends, then finds the account.
      # The account's storefront inbox is made in the same transaction, so
      # there is never a new account without it; an account that existed or is
      # restored gets none here (docs/app-storefront-chat.md §2.1).
      def create
        ActiveRecord::Base.transaction(requires_new: true) do
          row = ProvisionedAccount.create!(shop_domain: @payload.shop_domain, state: 'active', store_access_url: @payload.store_access_url)
          user, created = administrator
          account = build_account(user)
          row.update!(account: account)
          StorefrontChat.create!(row, account)
          Result.new(row: row, account: account, outcome: 'created', admin_is_member: true,
                     password_setup_url: (password_link(user) if created))
        end
      end

      def existing(row)
        row.with_lock do
          row.update!(store_access_url: @payload.store_access_url) if @payload.store_access_url
          row.active? ? existed(row, row.account) : restore(row, row.account)
        end
      end

      # Nothing is created and nobody is added. A user of the account who has
      # never signed in gets a new link, since the answer that carried the
      # first one may have been lost; the new one replaces it.
      def existed(row, account)
        user = User.from_email(@payload.admin_email)
        member = user.present? && AccountUser.exists?(account_id: account.id, user_id: user.id)
        Result.new(row: row, account: account, outcome: 'existed', admin_is_member: member,
                   password_setup_url: (password_link(user) if member && never_signed_in?(user)))
      end

      # The people of the earlier install may be gone, so the person named now
      # becomes an administrator next to whoever was there.
      def restore(row, account)
        account.update!(status: :active)
        row.update!(state: 'active')
        user, created = administrator
        membership = AccountUser.find_or_initialize_by(account_id: account.id, user_id: user.id)
        membership.update!(role: :administrator)
        Result.new(row: row, account: account, outcome: 'restored', admin_is_member: true,
                   password_setup_url: (password_link(user) if created || never_signed_in?(user)))
      end

      # No session was ever given to them: the login page counts its sign-ins
      # (Devise's sign_in_count), and every session, the password page's
      # included, is a token of the user.
      def never_signed_in?(user)
        user.sign_in_count.to_i.zero? && user.tokens.blank?
      end

      # The user with that email, or a new confirmed one. A new user gets a
      # random password that is kept nowhere, so no password signs them in
      # until they set one; no confirmation or invitation letter is sent.
      # Nothing of a known user is touched.
      def administrator
        user = User.from_email(@payload.admin_email)
        return [user, false] if user

        user = User.new(name: @payload.admin_name, email: @payload.admin_email, password: unusable_password)
        user.skip_confirmation!
        user.save!
        [user, true]
      end

      # Chatwoot's own account building, so a new account gets everything
      # Chatwoot and the overlay set up for one. The store's name, language and
      # time zone are used here and never afterwards.
      def build_account(user)
        current = Current.account
        _user, account = AccountBuilder.new(account_name: @payload.shop_name, email: user.email, user: user).perform
        account.locale = @payload.locale if Account.locales.key?(@payload.locale)
        account.custom_attributes = account.custom_attributes.merge('timezone' => @payload.timezone) if known_timezone?
        account.save! if account.changed?
        account
      ensure
        Current.account = current
      end

      def known_timezone?
        @payload.timezone.present? && TZInfo::Timezone.all_identifiers.include?(@payload.timezone)
      end

      # The helpdesk's own password page with a Devise reset token made now:
      # single use, and valid for the installation's `reset_password_within`.
      def password_link(user)
        token = user.send(:set_reset_password_token)
        "#{Provisioning.helpdesk_url}/app/auth/password/edit?#{{ reset_password_token: token }.to_query}"
      end

      def unusable_password
        "#{SecureRandom.alphanumeric(48)}aA1!"
      end
    end
  end
end
