# frozen_string_literal: true

module Inclamo
  module TeamQueues
    # `sla-overdue`: the label that carries what Chatwoot's filter cannot see
    # (design D3). A conversation has it while a missed SLA target is still
    # unmet: the first response was missed and nobody has answered, or the
    # resolution was missed and the conversation is not resolved. `sla-missed`
    # (Inclamo::Sla) is another thing: it stays for good once a target was missed.
    #
    # The label is written here and at the SLA mark of a missed target, always
    # under the conversation's row lock (as Inclamo::Ai::Labels adds the AI
    # agent's), so a label somebody else adds at the same moment is kept. A
    # write happens only when the label has to change: each one is a
    # conversation update the store's automation rules see. Nothing here fails
    # its caller, and nothing here is called from a label's own change.
    module Markers
      # A timer whose missed target is still unmet. Matches the partial index
      # index_inclamo_sla_timers_overdue.
      OVERDUE = <<~SQL.squish.freeze
        inclamo_sla_timers.stopped_at IS NULL
        AND ((inclamo_sla_timers.first_response_missed_at IS NOT NULL AND inclamo_sla_timers.first_response_at IS NULL)
             OR (inclamo_sla_timers.resolution_missed_at IS NOT NULL AND inclamo_sla_timers.resolved_at IS NULL))
      SQL
      LABELLED = <<~SQL.squish.freeze
        EXISTS (SELECT 1 FROM taggings JOIN tags ON tags.id = taggings.tag_id
                WHERE taggings.taggable_type = 'Conversation' AND taggings.taggable_id = conversations.id
                  AND taggings.context = 'labels' AND tags.name = :label)
      SQL
      TIMER_OVERDUE = "EXISTS (SELECT 1 FROM inclamo_sla_timers WHERE inclamo_sla_timers.conversation_id = conversations.id AND #{OVERDUE})".freeze
      # Conversations one run of the SLA check brings in step at most, in each
      # direction, oldest first; the next run goes on. Keeps the first run
      # after an upgrade, with a backlog of missed targets, from changing every
      # such conversation in one job.
      RECONCILE_BATCH = 200

      module_function

      # Brings the label in step with the conversation's timer.
      def sync_overdue(conversation_id)
        conversation = Conversation.find_by(id: conversation_id)
        return unless conversation
        # In step already: no lock, no write.
        return if overdue?(conversation) == conversation.label_list.include?(OVERDUE_LABEL)

        Installer.label!(conversation.account, OVERDUE_LABEL)
        # The row lock reloads the conversation: what is due and which labels
        # it has are read again once nobody else can change them.
        conversation.with_lock do
          due = overdue?(conversation)
          current = conversation.label_list.to_a
          next if due == current.include?(OVERDUE_LABEL)

          conversation.update!(label_list: due ? current + [OVERDUE_LABEL] : current - [OVERDUE_LABEL])
        end
      rescue StandardError => e
        report(e, conversation_id)
      end

      def overdue?(conversation)
        !conversation.resolved? && Inclamo::SlaTimer.where(conversation_id: conversation.id).where(OVERDUE).exists?
      end

      # Part of the SLA check, both ways: the label is put where it is due and
      # missing (taken off by hand, or the write at the miss failed), and taken
      # off where it is carried and nothing is overdue any more (a write that
      # failed when the target was met, the conversation resolved or the timer
      # stopped). Conversations already in step are not touched.
      def reconcile_overdue(limit: RECONCILE_BATCH)
        lacking = Conversation.where.not(status: :resolved).where(TIMER_OVERDUE).where("NOT #{LABELLED}", label: OVERDUE_LABEL)
        stale = Conversation.where(LABELLED, label: OVERDUE_LABEL)
                            .where("conversations.status = :resolved OR NOT #{TIMER_OVERDUE}", resolved: Conversation.statuses[:resolved])
        [lacking, stale].each { |scope| scope.order(:id).limit(limit).pluck(:id).each { |id| sync_overdue(id) } }
      rescue StandardError => e
        report(e)
      end

      def report(error, conversation_id = nil)
        Rails.logger.error("[inclamo] sla-overdue not updated#{" for conversation #{conversation_id}" if conversation_id}: " \
                           "#{error.class.name}: #{error.message}")
        ChatwootExceptionTracker.new(error).capture_exception
      end
    end
  end
end
