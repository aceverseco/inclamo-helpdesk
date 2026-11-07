# frozen_string_literal: true

module Inclamo
  module Sla
    # Per policy, for the last days: the conversations it was applied to and
    # how many of them met and missed each target (design D7). A timer still
    # running counts as neither. Computed on each request, nothing is stored.
    class Summary
      DAYS = [7, 30].freeze

      COLUMNS = Inclamo::SlaTimer::TARGETS.flat_map do |target|
        reached = target == 'first_response' ? 'first_response_at' : 'resolved_at'
        [
          "COUNT(*) FILTER (WHERE #{target}_seconds IS NOT NULL)",
          "COUNT(*) FILTER (WHERE #{target}_seconds IS NOT NULL AND #{reached} IS NOT NULL AND #{target}_missed_at IS NULL)",
          "COUNT(*) FILTER (WHERE #{target}_seconds IS NOT NULL AND #{target}_missed_at IS NOT NULL)"
        ]
      end.freeze

      def initialize(account, days:, now: Time.current)
        @account = account
        @days = days
        @now = now
      end

      def as_json(*)
        policies = Inclamo::SlaPolicy.where(account_id: @account.id).ordered.to_a
        rows = Inclamo::SlaTimer.where(policy_id: policies.map(&:id), started_at: (@now - @days.days)..)
                                .group(:policy_id)
                                .pluck(:policy_id, Arel.sql('COUNT(*)'), *COLUMNS.map { |column| Arel.sql(column) })
                                .index_by(&:first)
        policies.map { |policy| row(policy, rows[policy.id]) }
      end

      private

      def row(policy, counts)
        _, conversations, *by_target = counts || [policy.id, 0, *Array.new(COLUMNS.size, 0)]
        first_response, resolution = by_target.each_slice(3).to_a
        {
          id: policy.id, name: policy.name, conversations: conversations,
          first_response: share(policy.first_response_seconds, *first_response), resolution: share(policy.resolution_seconds, *resolution)
        }
      end

      # nil when the policy has no such target and no timer of the period had
      # one; a target without conversations in the period has no percentage.
      def share(target_seconds, total, met, missed)
        return nil if total.zero? && target_seconds.nil?

        { total: total, met: met, missed: missed, running: total - met - missed, met_percent: total.zero? ? nil : (met * 100.0 / total).round }
      end
    end
  end
end
