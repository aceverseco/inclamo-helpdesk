# frozen_string_literal: true

module Inclamo
  # The team queues every account starts with (capability team-queues, design
  # D1 and D3). A queue lists the open conversations with a priority or with
  # any of its labels. READY is the one place that says which.
  module TeamQueues
    # Kept by TeamQueues::Markers while a missed SLA target is still unmet.
    OVERDUE_LABEL = 'sla-overdue'
    # Colours of labels the installer creates; the others take Chatwoot's default.
    LABEL_COLORS = { OVERDUE_LABEL => '#E5484D' }.freeze
    DEFAULT_LABEL_COLOR = '#1f93ff'

    # key => what the queue lists, in the shipped order. `labels`: a
    # conversation with any one of them is listed (Chatwoot's filter matches a
    # label condition with several values as "any of"). Labels starting with
    # `inclamo_` are the AI agent's own (Inclamo::Ai::LABELS, and the labels it
    # adds per request type); the installer does not create those.
    READY = {
      'urgent' => { priority: 'urgent' },
      'ai_handover' => { labels: %w[inclamo_handover inclamo_error inclamo_limit] },
      'overdue' => { labels: [OVERDUE_LABEL] },
      'delivery' => { labels: %w[delivery inclamo_intent_delivery] },
      'cancellation' => { labels: %w[cancellation inclamo_intent_cancellation] },
      'damage' => { labels: %w[damage inclamo_intent_damage] },
      'missing_parts' => { labels: %w[missing-parts inclamo_intent_missing_parts] },
      'return' => { labels: %w[return inclamo_intent_return] }
    }.freeze

    module_function

    def ready?(key)
      READY.key?(key.to_s)
    end

    # The labels the installer creates: every queue label that is not the AI agent's.
    def labels
      READY.values.flat_map { |definition| definition[:labels].to_a }.uniq.grep_v(Inclamo::Ai::LABEL_FORMAT)
    end

    def shipped_name(key)
      I18n.t("inclamo.team_queues.names.#{key}")
    end

    def shipped_position(key)
      READY.keys.index(key.to_s) + 1
    end

    # The payload of Chatwoot's conversation filter (`POST conversations/filter`,
    # the `query` of a saved folder): open conversations with the priority or
    # the label. The last condition carries no operator, as Chatwoot requires.
    def shipped_query(key)
      definition = READY.fetch(key.to_s)
      attribute, values = definition[:priority] ? ['priority', [definition[:priority]]] : ['labels', definition[:labels]]
      { 'payload' => [condition('status', ['open'], 'and'), condition(attribute, values)] }
    end

    def condition(attribute, values, operator = nil)
      {
        'attribute_key' => attribute, 'filter_operator' => 'equal_to', 'values' => values,
        'attribute_model' => 'standard', 'custom_attribute_type' => ''
      }.merge(operator ? { 'query_operator' => operator } : {})
    end

    # How many conversations the queue lists for this staff member: the count
    # Chatwoot's filter gives with the queue's payload, so the number and the
    # opened list cannot disagree (design D5).
    def count(queue, user)
      params = { payload: queue.query['payload'], page: 1 }.with_indifferent_access
      ::Conversations::FilterService.new(params, user, queue.account).perform[:count][:all_count]
    end
  end
end
