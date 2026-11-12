# frozen_string_literal: true

# The policy applied to one conversation, with its targets copied at that
# moment, and what happened to each target (capability sla-timers).
class Inclamo::SlaTimer < ApplicationRecord
  TARGETS = %w[first_response resolution].freeze

  # A target still running; each condition matches a partial index of the table.
  RUNNING = {
    'first_response' => 'stopped_at IS NULL AND first_response_seconds IS NOT NULL ' \
                        'AND first_response_at IS NULL AND first_response_missed_at IS NULL',
    'resolution' => 'stopped_at IS NULL AND resolution_seconds IS NOT NULL ' \
                    'AND resolved_at IS NULL AND resolution_missed_at IS NULL'
  }.freeze

  # The business hours of the timer's inbox (its time zone, the switch and the
  # hours of each day) changed since its deadlines were stored. A minute of
  # margin covers an edit committed while they were being computed.
  HOURS_CHANGED = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM conversations JOIN inboxes ON inboxes.id = conversations.inbox_id
            WHERE conversations.id = inclamo_sla_timers.conversation_id
              AND (inboxes.updated_at > inclamo_sla_timers.due_computed_at - interval '1 minute'
                   OR EXISTS (SELECT 1 FROM working_hours WHERE working_hours.inbox_id = inboxes.id
                              AND working_hours.updated_at > inclamo_sla_timers.due_computed_at - interval '1 minute')))
  SQL

  belongs_to :conversation
  belongs_to :policy, class_name: 'Inclamo::SlaPolicy', optional: true, inverse_of: :timers

  scope :running, -> { where(RUNNING.values.map { |condition| "(#{condition})" }.join(' OR ')) }
  # Not stopped, with a target not reached yet: still running, or already missed.
  scope :unfinished, lambda {
    where('stopped_at IS NULL AND ((first_response_seconds IS NOT NULL AND first_response_at IS NULL) ' \
          'OR (resolution_seconds IS NOT NULL AND resolved_at IS NULL))')
  }

  # Timers with a target that may have passed by `now`. Counting business hours
  # only ever makes a deadline later, so plain time is the first cut. A
  # business-hours timer is then left out until the deadline the check stored
  # for it, unless its inbox's hours changed since (design D3: the deadline
  # follows the hours as they are). The clock decides.
  scope :maybe_due, lambda { |now|
    where(TARGETS.map do |target|
      "(#{RUNNING[target]} AND started_at + #{target}_seconds * interval '1 second' <= :now " \
        "AND (NOT business_hours_only OR due_computed_at IS NULL OR #{target}_due_at <= :now OR #{HOURS_CHANGED}))"
    end.join(' OR '), now: now)
  }

  def target_seconds(target)
    public_send("#{target}_seconds")
  end

  # When the target was reached: the first human reply, or the first resolution.
  def reached_at(target)
    target == 'first_response' ? first_response_at : resolved_at
  end

  def missed_at(target)
    public_send("#{target}_missed_at")
  end

  def clock
    @clock ||= Inclamo::Sla::Clock.new(inbox: conversation.inbox, business_hours_only: business_hours_only)
  end

  # The moment the target passes; nil without that target, or when the inbox's
  # business hours never open.
  def deadline(target)
    seconds = target_seconds(target)
    seconds && clock.deadline(started_at, seconds)
  end

  # The deadlines as computed now, kept for the periodic check only: the
  # sidebar and the check itself always compute them afresh. `computed_at` is
  # a moment before the inbox's hours were read.
  def due_attributes(computed_at)
    { first_response_due_at: deadline('first_response'), resolution_due_at: deadline('resolution'), due_computed_at: computed_at }
  end

  def store_due!(computed_at)
    self.class.where(id: id).update_all(due_attributes(computed_at)) # rubocop:disable Rails/SkipsModelValidations
  end
end
