# frozen_string_literal: true

module Inclamo
  module Erasure
    # "Shopify asked to erase the store" (docs/app-store-erasure.md §3): a
    # suspended account is given the time after which it is destroyed, counted
    # from the first accepted request; a repetition answers the same time and
    # moves nothing. Nothing is destroyed here. An active account is refused:
    # the store installed the app again before the request arrived.
    #
    # Answers Answer(state:, outcome:, body:), or raises AccountActive.
    class Schedule
      class AccountActive < StandardError; end

      Answer = Struct.new(:state, :outcome, :body, keyword_init: true)

      def initialize(shop_domain, now: Time.current)
        @shop_domain = shop_domain
        @now = now
      end

      def call
        row = Provisioning.store_domain(@shop_domain) && ProvisionedAccount.for_store(@shop_domain)
        return answer('none', 'none') unless row

        row.with_lock do
          case row.state
          when 'erased' then answer('erased', 'erased', erased_at: time(row.erased_at))
          when 'erasing' then answer('erasing', 'erasing')
          else scheduled(row)
          end
        end
      end

      private

      # Only an account the app's removal suspended, and that is suspended
      # still, is erased by this channel.
      def scheduled(row)
        raise AccountActive unless row.suspended? && row.account&.suspended?

        schedule!(row) unless row.erase_after
        answer('scheduled', 'erasure_scheduled', erase_after: time(row.erase_after))
      end

      def schedule!(row)
        row.update!(erase_after: (@now + Erasure.store_wait).change(usec: 0))
        Inclamo::ErasureRequest.scheduled_store(row.shop_domain)&.update!(state: 'cancelled', completed_at: @now)
        Inclamo::ErasureRequest.create!(kind: 'store', shop_domain: row.shop_domain, account_id: row.account_id, state: 'scheduled',
                                        received_at: @now)
      end

      def answer(state, outcome, **fields)
        Answer.new(state: state, outcome: outcome, body: { contract: Provisioning::CONTRACT, state: state, **fields })
      end

      def time(value)
        value&.utc&.iso8601
      end
    end
  end
end
