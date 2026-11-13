# frozen_string_literal: true

module Inclamo
  module TeamQueues
    # For the "SLA overview" widget (capability sla-urgency-widget): per
    # visible team queue, how many of the open conversations it lists for this
    # staff member are overdue, due soon, or neither, by the rule of the SLA
    # badge (Inclamo::Sla::Urgency).
    #
    # The conversations are those of Chatwoot's filter with the queue's own
    # payload, for the same person, so the three numbers add up to the count
    # the navigation shows next to the queue.
    module SlaOverview
      # Timers with an unmet target looked at per queue. A queue with more of
      # them is counted for CAP of them and says so (`capped`): its overdue and
      # soon numbers are then at least what is shown.
      CAP = 2_000

      module_function

      def call(account, user, now: Time.current)
        queues = Inclamo::TeamQueue.where(account_id: account.id).visible.ordered
        # A conversation in several queues is one conversation in the totals.
        seen = { 'overdue' => Set.new, 'soon' => Set.new }
        rows = queues.map { |queue| row(queue, user, now, seen) }
        { queues: rows, totals: { overdue: seen['overdue'].size, soon: seen['soon'].size },
          policies: Inclamo::SlaPolicy.exists?(account_id: account.id), cap: CAP }
      end

      # Unknown numbers (nil) for a queue Chatwoot's filter does not accept:
      # one such queue must not take the widget down (as TeamQueues.count).
      def row(queue, user, now, seen = nil)
        shown = { id: queue.id, key: queue.key, name: queue.name }
        total, relation = listed(queue, user)
        return shown.merge(total: nil, overdue: nil, soon: nil, other: nil, capped: false) if total.nil?

        found, capped = levels_of(relation, now)
        levels = found.transform_values(&:size)
        found.each { |level, ids| seen[level].merge(ids) } if seen
        # The count and the timers are read a moment apart: never below zero.
        shown.merge(total: total, overdue: levels['overdue'], soon: levels['soon'],
                    other: [total - levels['overdue'] - levels['soon'], 0].max, capped: capped)
      rescue StandardError => e
        Rails.logger.error("[inclamo] team queue #{queue.id} not counted by SLA: #{e.class.name}: #{e.message}")
        ChatwootExceptionTracker.new(e, account: queue.account).capture_exception
        shown.merge(total: nil, overdue: nil, soon: nil, other: nil, capped: false)
      end

      # The queue's count and its conversations, from one run of Chatwoot's
      # filter. The service keeps its unpaged relation in @conversations; the
      # contract spec of the queues fails the build of an upgrade that changes
      # this.
      def listed(queue, user)
        payload = queue.query.is_a?(Hash) ? queue.query['payload'] : nil
        return [nil, nil] unless payload.is_a?(Array) && payload.any? && payload.all?(Hash)

        service = ::Conversations::FilterService.new({ payload: payload, page: 1 }.with_indifferent_access, user, queue.account)
        total = service.perform[:count][:all_count]
        [total, service.instance_variable_get(:@conversations).except(:includes, :preload, :order)]
      end

      # The conversations of the queue that are overdue and that are soon.
      # Only a timer with a target still unmet can be overdue or soon, so only
      # those are read: every one of the queue's, whatever its length, up to
      # CAP. The presenter's clock reads the inbox and its business hours.
      def levels_of(conversations, now)
        levels = { 'overdue' => [], 'soon' => [] }
        timers = Inclamo::SlaTimer.unfinished.where(conversation_id: conversations.select('conversations.id'))
                                  .includes(conversation: { inbox: :working_hours }).order(:id).limit(CAP + 1).to_a
        timers.first(CAP).each do |timer|
          level = Inclamo::Sla::Urgency.level(timer, now: now)
          levels[level] << timer.conversation_id if levels.key?(level)
        end
        [levels, timers.size > CAP]
      end
    end
  end
end
