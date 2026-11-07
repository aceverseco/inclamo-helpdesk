# frozen_string_literal: true

module Inclamo
  module Sla
    # What the "SLA" section of a conversation shows, as of `now`: per target
    # its state and the time left, taken or over. The sidebar counts down
    # locally from this and asks again when `next_change_at` comes.
    #
    # States: running, paused (outside business hours), met, missed, stopped
    # (the policy was deleted while the target was running).
    class TimerPresenter
      def initialize(timer, now: Time.current)
        @timer = timer
        @now = now
      end

      def as_json(*)
        {
          policy_name: @timer.policy_name,
          business_hours_only: @timer.business_hours_only,
          started_at: @timer.started_at,
          stopped: @timer.stopped_at.present?,
          next_change_at: @timer.stopped_at ? nil : clock.next_change(@now),
          first_response: target('first_response'),
          resolution: target('resolution')
        }
      end

      private

      def clock
        @timer.clock
      end

      def target(name)
        seconds = @timer.target_seconds(name)
        return nil unless seconds

        deadline = @timer.deadline(name)
        shown = { target_seconds: seconds, deadline_at: deadline }
        reached = @timer.reached_at(name)
        return shown.merge(reached_state(name, seconds, deadline, reached)) if reached

        shown.merge(open_state(name, seconds, deadline))
      end

      # Met in time, or met after the target passed: then it stays missed.
      def reached_state(name, seconds, deadline, reached)
        took = clock.elapsed(@timer.started_at, reached)
        late = @timer.missed_at(name).present? || (deadline.present? && reached > deadline)
        { state: late ? 'missed' : 'met', took_seconds: took, over_seconds: late ? [took - seconds, 0].max : nil, counting: false }
      end

      def open_state(name, seconds, deadline)
        until_moment = @timer.stopped_at || @now
        elapsed = clock.elapsed(@timer.started_at, until_moment)
        counting = @timer.stopped_at.nil? && clock.counting_at?(@now)
        if @timer.missed_at(name).present? || (deadline.present? && deadline <= until_moment)
          return { state: 'missed', over_seconds: [elapsed - seconds, 0].max, counting: counting }
        end
        return { state: 'stopped', remaining_seconds: seconds - elapsed, counting: false } if @timer.stopped_at

        { state: counting ? 'running' : 'paused', remaining_seconds: seconds - elapsed, counting: counting }
      end
    end
  end
end
