# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The one-time address of an entry (docs/app-admin-entry.md §2):
    #   {FRONTEND_URL}/inclamo/entry/<token>
    # The token is 256 random bits and says nothing about the person. Redis
    # holds, under a digest of it, the user, the account and the store it
    # was made for, for LIFETIME seconds; taking it deletes it, and two
    # openings at the same instant cannot both have it. Neither
    # the token nor the address is written anywhere else.
    module EntryPass
      LIFETIME = 60
      PATH = '/inclamo/entry'
      KEY = 'INCLAMO_ENTRY::%<digest>s'
      TOKEN = /\A[A-Za-z0-9_-]{43}\z/

      Pass = Struct.new(:user_id, :account_id, :shop_domain, keyword_init: true)

      module_function

      def issue(user, account)
        token = SecureRandom.urlsafe_base64(32)
        shop_domain = ProvisionedAccount.find_by(account_id: account.id)&.shop_domain
        Redis::Alfred.set(key(token), { user_id: user.id, account_id: account.id, shop_domain: shop_domain }.to_json, ex: LIFETIME)
        "#{Provisioning.helpdesk_url}#{PATH}/#{token}"
      end

      # The pass the token was made for, gone from Redis from now on; nil for
      # a token that is unknown, used or past its life. Of two takers at the
      # same instant only the one whose delete removed the key has it, as
      # Chatwoot consumes its own one-time tokens.
      def take(token)
        return unless TOKEN.match?(token.to_s)

        raw = Redis::Alfred.get(key(token))
        return unless raw && Redis::Alfred.delete(key(token)).to_i.positive?

        Pass.new(**JSON.parse(raw).symbolize_keys.slice(:user_id, :account_id, :shop_domain))
      end

      def key(token)
        format(KEY, digest: Digest::SHA256.hexdigest(token.to_s))
      end
    end
  end
end
