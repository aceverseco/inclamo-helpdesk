# frozen_string_literal: true

module Inclamo
  # Accounts made on the request of the operator's store app (capability
  # app-provisioned-account, contract in docs/app-provisioning.md): the app
  # names a Shopify store and the person who asked, and the helpdesk creates,
  # finds, suspends or restores that store's account.
  #
  # The whole of it exists only where the operator set the shared secret. An
  # installation without it draws no route and answers as any unknown address.
  module Provisioning
    CONTRACT = 1
    SHOP_DOMAIN = /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/
    SECRET_BYTES = 32

    # Requests accepted in an hour (operator settings, with these defaults).
    LIMITS = {
      put: ['INCLAMO_APP_PROVISIONING_PUT_LIMIT', 30],
      store: ['INCLAMO_APP_PROVISIONING_STORE_LIMIT', 5],
      get: ['INCLAMO_APP_PROVISIONING_GET_LIMIT', 300]
    }.freeze

    class LinkRefused < StandardError; end

    class << self
      def enabled?
        secret.present?
      end

      # The secrets a signature is checked against: the current one and, while
      # the app is being switched over, the previous one.
      def secrets
        return [] unless enabled?

        [secret, usable(ENV.fetch('INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS', nil))].compact
      end

      def limit(name)
        variable, default = LIMITS.fetch(name)
        value = Integer(ENV.fetch(variable, '').strip, 10, exception: false)
        value&.positive? ? value : default
      end

      # The address people open, as the operator configured it.
      def helpdesk_url
        ENV.fetch('FRONTEND_URL', '').strip.chomp('/')
      end

      def store_domain(text)
        domain = text.to_s.strip.downcase
        domain if SHOP_DOMAIN.match?(domain)
      end

      # Ties an account made by hand to its store, so the store's later request
      # finds it instead of creating a second one.
      def link!(shop_domain, account_id)
        domain = store_domain(shop_domain)
        raise LinkRefused, "#{shop_domain.to_s.inspect} is not a myshopify.com domain" unless domain

        account = Account.find_by(id: Integer(account_id.to_s, 10, exception: false))
        raise LinkRefused, "no account #{account_id.to_s.inspect}" unless account
        raise LinkRefused, "#{domain} is already linked to an account" if ProvisionedAccount.exists?(shop_domain: domain)
        raise LinkRefused, "account #{account.id} is already linked to a store" if ProvisionedAccount.exists?(account_id: account.id)

        ProvisionedAccount.create!(shop_domain: domain, account: account, state: account.suspended? ? 'suspended' : 'active')
      rescue ActiveRecord::RecordNotUnique
        raise LinkRefused, 'the domain or the account is already linked'
      end

      private

      def secret
        usable(ENV.fetch('INCLAMO_APP_PROVISIONING_SECRET', nil))
      end

      # A secret shorter than the contract's 32 bytes is treated as not set.
      def usable(value)
        value = value.to_s.strip
        value if value.bytesize >= SECRET_BYTES
      end
    end
  end
end
