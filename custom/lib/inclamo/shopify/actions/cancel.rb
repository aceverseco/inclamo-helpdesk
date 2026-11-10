# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Cancels the order. The store works on it in the background; we wait up
      # to ten seconds for it and otherwise report the cancellation as running.
      # A job that ends with the order not cancelled is the store's refusal.
      class Cancel < Base
        REASONS = %w[CUSTOMER DECLINED FRAUD INVENTORY STAFF OTHER].freeze
        RECORDED = %w[reason refund restock notify].freeze
        WAIT = 10 # seconds
        POLL = 1
        NOT_CANCELLED = 'the store finished without cancelling the order'

        def initialize(sleeper: ->(seconds) { sleep(seconds) }, **rest)
          super(**rest)
          @sleeper = sleeper
        end

        def call
          return :accepted if @order['cancelledAt'].present?

          # Once the store took the cancellation it is not sent again, also
          # when the store gave no job to follow.
          start unless @record.progress.key?('job_id')
          wait_for_the_store
        end

        # Reads the job and the order once, without waiting and without
        # sending the cancellation again.
        def resolve
          case standing
          when :cancelled then :accepted
          when :finished then raise Refused.new('not_cancelled', NOT_CANCELLED)
          else
            # Without the store's answer to the cancellation nothing says it took it.
            @record.progress.key?('job_id') ? :running : nil
          end
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
          remember!(job_id: answer.dig('job', 'id'))
        end

        def wait_for_the_store
          deadline = now + WAIT
          loop do
            state = standing
            return :accepted if state == :cancelled
            if now + POLL > deadline
              raise Refused.new('not_cancelled', NOT_CANCELLED) if state == :finished

              return :running
            end

            @sleeper.call(POLL)
          end
        end

        # :cancelled when the order is, :finished when the store's job is done
        # and the order is not cancelled, :working otherwise. The job is asked
        # first: an order read before the job ended may not show its end yet.
        def standing
          job_id = @record.progress['job_id']
          if job_id.present?
            job = @store.query(:job_status, { id: job_id })['job']
            return :working unless job.nil? || job['done']
          end
          fresh = @store.query(:order_details_limited, { id: @record.order_id })['order']
          return :cancelled if fresh && fresh['cancelledAt'].present?

          job_id.present? ? :finished : :working
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
