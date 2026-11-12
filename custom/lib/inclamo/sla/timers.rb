# frozen_string_literal: true

module Inclamo
  module Sla
    # What happens to a conversation's timer: it is applied when the
    # conversation is created, its targets are reached by the first human reply
    # and the first resolution, and a target that passes is marked once.
    #
    # Chatwoot's events are handled in the background, so a conversation can be
    # ahead of its timer: a reply already sent or a resolution already made that
    # no event has brought yet. Applying a timer and checking a target first
    # look at the conversation itself.
    module Timers
      # A conversation shown resolved whose resolution no event has recorded
      # yet: its event, which carries the exact moment, gets this long before the
      # check records the resolution at the conversation's last change instead.
      RESOLUTION_EVENT_GRACE = 10.minutes

      module_function

      # Applies the first covering policy, with its targets as they are now.
      def apply!(conversation)
        return if Inclamo::SlaTimer.exists?(conversation_id: conversation.id)

        policy = Inclamo::SlaPolicy.covering(conversation)
        return unless policy

        computed_at = Time.current
        timer = Inclamo::SlaTimer.new(
          conversation: conversation, policy: policy, policy_name: policy.name, business_hours_only: policy.business_hours_only,
          first_response_seconds: policy.first_response_seconds, resolution_seconds: policy.resolution_seconds,
          started_at: conversation.created_at
        )
        timer.assign_attributes(timer.due_attributes(computed_at))
        timer.save!
        catch_up!(timer, conversation)
        timer
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def replied!(message)
        return unless HumanReply.match?(message)

        timer = Inclamo::SlaTimer.find_by(conversation_id: message.conversation_id, stopped_at: nil, first_response_at: nil)
        reached!(timer, 'first_response', message.created_at) if timer
      end

      def resolved!(conversation, at)
        timer = Inclamo::SlaTimer.find_by(conversation_id: conversation.id, stopped_at: nil, resolved_at: nil)
        reached!(timer, 'resolution', at) if timer
      end

      # Marks every target among `timers` that has passed by `now`; run by
      # Inclamo::SlaCheckJob, and for the timers of a policy being deleted. A
      # target that cannot be marked is reported and left for the next run; the
      # others are checked all the same.
      def check_due!(now = Time.current, timers = nil)
        computed_at = Time.current
        (timers || Inclamo::SlaTimer.all).maybe_due(now).includes(conversation: { inbox: :working_hours }).find_each do |timer|
          Inclamo::SlaTimer::TARGETS.each { |target| check!(timer, target, now) }
          # Its deadlines as now computed: later runs leave it alone until then
          # (SlaTimer.maybe_due), unless the inbox's hours change.
          timer.store_due!(computed_at) if timer.business_hours_only?
        end
        # The team queue "Overdue": its label is brought in step with the
        # timers, a bounded number of conversations a run. Nothing is written
        # where nothing changed.
        Inclamo::TeamQueues::Markers.reconcile_overdue unless timers
      end

      def check!(timer, target, now)
        return unless running?(timer, target)

        deadline = timer.deadline(target)
        return unless deadline && deadline <= now
        return if reached_meanwhile?(timer, target, now)

        missed!(timer, target, deadline)
      rescue StandardError => e
        Rails.logger.error("[inclamo] SLA target not checked: timer #{timer.id} #{target}: #{e.class.name}: #{e.message}")
        ChatwootExceptionTracker.new(e, account: timer.conversation&.account).capture_exception
      end

      # Records the first reply or resolution, once. One that came after the
      # deadline marks the target as missed, if the check has not done so yet.
      # A mark that fails takes the record back with it, so that the check finds
      # the target again.
      def reached!(timer, target, at)
        column = reached_column(target)
        Inclamo::SlaTimer.transaction(requires_new: true) do
          unrecorded = Inclamo::SlaTimer.where(id: timer.id, column => nil, stopped_at: nil)
          next if unrecorded.update_all(column => at, updated_at: Time.current).zero? # rubocop:disable Rails/SkipsModelValidations

          timer.reload
          deadline = timer.deadline(target)
          missed!(timer, target, deadline, reached: true) if deadline && at > deadline
        end
        # A target met, in time or late, is no longer overdue (team queue "Overdue").
        Inclamo::TeamQueues::Markers.sync_overdue(timer.conversation_id)
      end

      # Sets the moment the target passed, then adds the label and the note, in
      # one transaction. Only the call that sets it marks the conversation, so a
      # target is marked once however often it is checked; a mark that fails
      # leaves the moment unset, to be tried again. The check (`reached: false`)
      # does not mark a target reached since it read the timer.
      def missed!(timer, target, at, reached: false)
        column = :"#{target}_missed_at"
        unmarked = { id: timer.id, column => nil, stopped_at: nil }
        unmarked[reached_column(target)] = nil unless reached
        Inclamo::SlaTimer.transaction(requires_new: true) do
          marked = Inclamo::SlaTimer.where(unmarked).update_all(column => at, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          mark_conversation!(timer, target, overdue: !reached) if marked.positive?
        end
        Inclamo::TeamQueues::Markers.sync_overdue(timer.conversation_id)
      end

      def running?(timer, target)
        timer.stopped_at.nil? && timer.target_seconds(target).present? && timer.reached_at(target).nil? && timer.missed_at(target).nil?
      end

      def reached_column(target)
        target == 'first_response' ? :first_response_at : :resolved_at
      end

      def first_human_reply(conversation)
        conversation.messages.outgoing.where(private: false).reorder(:created_at, :id).find { |message| HumanReply.match?(message) }
      end

      # A new timer takes what the conversation already shows: a human reply,
      # and a resolution. Chatwoot creates a blocked contact's conversation
      # resolved, with no event; and a resolution's event can be handled before
      # the timer exists. Its moment is the conversation's last change.
      def catch_up!(timer, conversation)
        reply = first_human_reply(conversation)
        reached!(timer, 'first_response', reply.created_at) if reply
        reached!(timer, 'resolution', conversation.updated_at) if conversation.resolved?
      end

      # Whether a target the timer still runs past its deadline was reached in
      # the conversation: a human reply is recorded at the moment it was sent,
      # in time or late. A resolution is left to its own event for a while, as
      # only the event knows when it happened.
      def reached_meanwhile?(timer, target, now)
        conversation = timer.conversation
        if target == 'first_response'
          reply = first_human_reply(conversation)
          reached!(timer, target, reply.created_at) if reply
          return reply.present?
        end
        return false unless conversation.resolved?

        reached!(timer, target, conversation.updated_at) if conversation.updated_at <= now - RESOLUTION_EVENT_GRACE
        true
      end

      # The label `sla-missed` and a private note naming the target and its length.
      # A target the check found unmet (`overdue`) also gets the team queues'
      # `sla-overdue` in the same write, so the conversation changes once and
      # the store's automation rules see one update, not two.
      def mark_conversation!(timer, target, overdue: false)
        # A fresh record: Chatwoot's label persistence must not reuse an instance.
        conversation = Conversation.find(timer.conversation_id)
        label!(conversation.account)
        Inclamo::TeamQueues::Installer.label!(conversation.account, Inclamo::TeamQueues::OVERDUE_LABEL) if overdue
        # Under the row lock, which reloads the conversation, so a label added
        # by somebody else at this moment is kept (as Inclamo::Ai::Labels.add).
        conversation.with_lock do
          wanted = [LABEL]
          wanted << Inclamo::TeamQueues::OVERDUE_LABEL if overdue && !conversation.resolved?
          current = conversation.label_list.to_a
          missing = wanted - current
          conversation.update!(label_list: current + missing) if missing.any?
        end
        note = I18n.t("inclamo.sla.notes.#{target}", policy: timer.policy_name, target: Sla.duration_words(timer.target_seconds(target)))
        Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform
      end

      # The account's label, created on first use (design D6). Created in a
      # savepoint of its own: a label made at the same moment elsewhere must not
      # spoil the transaction of the mark.
      def label!(account)
        account.labels.find_by(title: LABEL) || Label.transaction(requires_new: true) do
          account.labels.create!(title: LABEL, color: LABEL_COLOR, description: I18n.t('inclamo.sla.label_description'), show_on_sidebar: true)
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        account.labels.find_by(title: LABEL) || raise
      end
    end
  end
end
