# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Cancels the order. The store works on it in the background; we wait up
      # to ten seconds for it and otherwise report the cancellation as running.
      class Cancel < Base
        REASONS = %w[CUSTOMER DECLINED FRAUD INVENTORY STAFF OTHER].freeze
        RECORDED = %w[reason refund restock notify].freeze
        WAIT = 10 # seconds
        POLL = 1

        def initialize(sleeper: ->(seconds) { sleep(seconds) }, **rest)
          super(**rest)
          @sleeper = sleeper
        end

        def call
          return :accepted if @order['cancelledAt'].present?

          start unless @record.progress['job_id']
          wait_for_the_store
        end

        private

        def start
          reason = params['reason'].to_s.upcase
          raise Refused, 'invalid_reason' unless REASONS.include?(reason)

          answer = @store.query(:order_cancel, {
                                  orderId: @record.order_id, reason: reason, restock: params['restock'] == true,
                                  refundMethod: params['refund'] == true ? { originalPaymentMethodsRefund: true } : nil,
                                  notifyCustomer: params['notify'] == true, staffNote: nil
                                })['orderCancel']
          user_errors!(answer['orderCancelUserErrors'])
          remember!(job_id: answer.dig('job', 'id'), job_done: answer.dig('job', 'done') == true)
        end

        def wait_for_the_store
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT
          loop do
            return :accepted if cancelled_now?
            return :running if Process.clock_gettime(Process::CLOCK_MONOTONIC) + POLL > deadline

            @sleeper.call(POLL)
          end
        end

        def cancelled_now?
          job = @store.query(:job_status, { id: @record.progress['job_id'] })['job']
          return false unless job.nil? || job['done']

          fresh = @store.query(:order_details_limited, { id: @record.order_id })['order']
          fresh && fresh['cancelledAt'].present?
        end
      end
    end
  end
end
