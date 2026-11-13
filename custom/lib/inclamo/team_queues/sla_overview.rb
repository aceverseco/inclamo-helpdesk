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
      # Conversations looked at per queue. A longer queue is counted for its
      # first CAP conversations and says so (`capped`).
      CAP = 2_000

      module_function

      def call(account, user, now: Time.current)
        queues = Inclamo::TeamQueue.where(account_id: account.id).visible.ordered
        { queues: queues.map { |queue| row(queue, user, now) },
          policies: Inclamo::SlaPolicy.exists?(account_id: account.id), cap: CAP }
      end

      # Unknown numbers (nil) for a queue Chatwoot's filter does not accept:
      # one such queue must not take the widget down (as TeamQueues.count).
      def row(queue, user, now)
        shown = { id: queue.id, key: queue.key, name: queue.name }
        total, ids = listed(queue, user)
        return shown.merge(total: nil, overdue: nil, soon: nil, other: nil, capped: false) if total.nil?

        levels = levels_of(ids, now)
        shown.merge(total: total, overdue: levels['overdue'], soon: levels['soon'],
                    other: total - levels['overdue'] - levels['soon'], capped: total > ids.size)
      rescue StandardError => e
        Rails.logger.error("[inclamo] team queue #{queue.id} not counted by SLA: #{e.class.name}: #{e.message}")
        ChatwootExceptionTracker.new(e, account: queue.account).capture_exception
        shown.merge(total: nil, overdue: nil, soon: nil, other: nil, capped: false)
      end

      # The queue's count and the ids of (at most CAP of) its conversations,
      # from one run of Chatwoot's filter. The service keeps its unpaged
      # relation in @conversations; the contract spec of the queues fails the
      # build of an upgrade that changes this.
      def listed(queue, user)
        payload = queue.query.is_a?(Hash) ? queue.query['payload'] : nil
        return [nil, []] unless payload.is_a?(Array) && payload.any? && payload.all?(Hash)

        service = ::Conversations::FilterService.new({ payload: payload, page: 1 }.with_indifferent_access, user, queue.account)
        total = service.perform[:count][:all_count]
        relation = service.instance_variable_get(:@conversations)
        [total, relation.except(:includes, :preload, :order).limit(CAP).pluck('conversations.id')]
      end

      # Only a timer with a target still unmet can be overdue or soon.
      def levels_of(conversation_ids, now)
        levels = { 'overdue' => 0, 'soon' => 0 }
        Inclamo::SlaTimer.unfinished.where(conversation_id: conversation_ids).includes(conversation: :inbox).find_each do |timer|
          level = Inclamo::Sla::Urgency.level(timer, now: now)
          levels[level] += 1 if levels.key?(level)
        end
        levels
      end
    end
  end
end
