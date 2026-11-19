# frozen_string_literal: true

module Inclamo
  module Erasure
    # How many of a store's requests about shoppers wait, are held or are
    # overdue (docs/app-store-erasure.md §6): the way the app follows them
    # without keeping a shopper's email. Numbers only; `overdue` counts the
    # requests not done 30 days after they were received, which are counted
    # among the waiting or held ones too. Nil for a store without an account.
    module ShopperCounts
      module_function

      def call(shop_domain, now: Time.current)
        row = Provisioning.store_domain(shop_domain) && ProvisionedAccount.for_store(shop_domain)
        account = row&.account if row && (row.active? || row.suspended?)
        return unless account

        unmet = Inclamo::ErasureRequest.where(shop_domain: row.shop_domain, account_id: account.id, state: %w[waiting held])
        overdue = unmet.where(received_at: ..(now - Shoppers::OVERDUE_AFTER))
        erasures = unmet.where(kind: 'shopper_erasure')
        data_requests = unmet.where(kind: 'shopper_data_request')
        {
          contract: Provisioning::CONTRACT,
          erasures: {
            waiting: erasures.where(state: 'waiting').count, held: erasures.where(state: 'held').count,
            overdue: overdue.where(kind: 'shopper_erasure').count
          },
          data_requests: { waiting: data_requests.where(state: 'waiting').count, overdue: overdue.where(kind: 'shopper_data_request').count },
          account_state: row.suspended? || account.suspended? ? 'suspended' : 'active'
        }
      end
    end
  end
end
