# frozen_string_literal: true

module Inclamo
  module Sla
    # What happens to a conversation's timer: it is applied when the
    # conversation is created, its targets are reached by the first human reply
    # and the first resolution, and a target that passes is marked once.
    module Timers
      module_function

      # Applies the first covering policy, with its targets as they are now.
      def apply!(conversation)
        return if Inclamo::SlaTimer.exists?(conversation_id: conversation.id)

        policy = Inclamo::SlaPolicy.covering(conversation)
        return unless policy

        timer = Inclamo::SlaTimer.create!(
          conversation: conversation, policy: policy, policy_name: policy.name, business_hours_only: policy.business_hours_only,
          first_response_seconds: policy.first_response_seconds, resolution_seconds: policy.resolution_seconds,
          started_at: conversation.created_at
        )
        # Chatwoot's events are handled in the background: a reply may be there already.
        reply = first_human_reply(conversation)
        reached!(timer, 'first_response', reply.created_at) if reply
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

      # Marks every target that has passed by `now`; run by Inclamo::SlaCheckJob.
      def check_due!(now = Time.current)
        Inclamo::SlaTimer.maybe_due(now).includes(conversation: { inbox: :working_hours }).find_each do |timer|
          Inclamo::SlaTimer::TARGETS.each do |target|
            next unless running?(timer, target)

            deadline = timer.deadline(target)
            missed!(timer, target, deadline) if deadline && deadline <= now
          end
        end
      end

      # Records the first reply or resolution, once. One that came after the
      # deadline marks the target as missed, if the check has not done so yet.
      def reached!(timer, target, at)
        column = target == 'first_response' ? :first_response_at : :resolved_at
        return if Inclamo::SlaTimer.where(id: timer.id, column => nil, stopped_at: nil).update_all(column => at, updated_at: Time.current).zero? # rubocop:disable Rails/SkipsModelValidations

        timer.reload
        deadline = timer.deadline(target)
        missed!(timer, target, deadline) if deadline && at > deadline
      end

      # Sets the moment the target passed. Only the call that sets it adds the
      # label and the note, so a target is marked once however often it is checked.
      def missed!(timer, target, at)
        column = :"#{target}_missed_at"
        return if Inclamo::SlaTimer.where(id: timer.id, column => nil, stopped_at: nil).update_all(column => at, updated_at: Time.current).zero? # rubocop:disable Rails/SkipsModelValidations

        mark_conversation!(timer, target)
      end

      def running?(timer, target)
        timer.stopped_at.nil? && timer.target_seconds(target).present? && timer.reached_at(target).nil? && timer.missed_at(target).nil?
      end

      def first_human_reply(conversation)
        conversation.messages.outgoing.where(private: false).reorder(:created_at, :id).find { |message| HumanReply.match?(message) }
      end

      # The label `sla-missed` and a private note naming the target and its length.
      def mark_conversation!(timer, target)
        # A fresh record: Chatwoot's label persistence must not reuse an instance.
        conversation = Conversation.find(timer.conversation_id)
        label!(conversation.account)
        conversation.add_labels([LABEL]) unless conversation.label_list.include?(LABEL)
        note = I18n.t("inclamo.sla.notes.#{target}", policy: timer.policy_name, target: Sla.duration_words(timer.target_seconds(target)))
        Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform
      end

      # The account's label, created on first use (design D6).
      def label!(account)
        account.labels.find_or_create_by!(title: LABEL) do |label|
          label.color = LABEL_COLOR
          label.description = I18n.t('inclamo.sla.label_description')
          label.show_on_sidebar = true
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        account.labels.find_by(title: LABEL) || raise
      end
    end
  end
end
