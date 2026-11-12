# frozen_string_literal: true

module Inclamo
  module TeamQueues
    # `sla-overdue`: the label that carries what Chatwoot's filter cannot see
    # (design D3). A conversation has it while a missed SLA target is still
    # unmet: the first response was missed and nobody has answered, or the
    # resolution was missed and the conversation is not resolved. `sla-missed`
    # (Inclamo::Sla) is another thing: it stays for good once a target was missed.
    #
    # Every write goes through here or through the SLA mark of a missed target,
    # is safe to repeat, writes nothing when nothing changes (each label write
    # is a conversation update the store's automation rules see), and never
    # fails its caller. Nothing here is called from a label's own change.
    module Markers
      # A timer whose missed target is still unmet.
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

      module_function

      # Brings the label in step with the conversation's timer.
      def sync_overdue(conversation_id)
        conversation = Conversation.find_by(id: conversation_id)
        return unless conversation

        overdue = !conversation.resolved? && Inclamo::SlaTimer.where(conversation_id: conversation.id).where(OVERDUE).exists?
        overdue ? add(conversation) : remove(conversation)
      rescue StandardError => e
        report(e, conversation_id)
      end

      # Puts the label back where it is due and missing (taken off by hand, or
      # not written when the target was missed); part of the SLA check. Only
      # conversations that lack it are touched.
      def reassert_overdue
        Conversation.where.not(status: :resolved).joins('JOIN inclamo_sla_timers ON inclamo_sla_timers.conversation_id = conversations.id')
                    .where(OVERDUE).where("NOT #{LABELLED}", label: OVERDUE_LABEL).pluck(:id).each { |id| sync_overdue(id) }
      rescue StandardError => e
        report(e)
      end

      # A fresh record each time: Chatwoot's label persistence must not reuse
      # an instance (see Inclamo::Sla::Timers.mark_conversation!).
      def add(conversation)
        return if conversation.label_list.include?(OVERDUE_LABEL)

        Installer.label!(conversation.account, OVERDUE_LABEL)
        conversation.add_labels([OVERDUE_LABEL])
      end

      def remove(conversation)
        return unless conversation.label_list.include?(OVERDUE_LABEL)

        conversation.update_labels(conversation.label_list - [OVERDUE_LABEL])
      end

      def report(error, conversation_id = nil)
        Rails.logger.error("[inclamo] sla-overdue not updated#{" for conversation #{conversation_id}" if conversation_id}: " \
                           "#{error.class.name}: #{error.message}")
        ChatwootExceptionTracker.new(error).capture_exception
      end
    end
  end
end
