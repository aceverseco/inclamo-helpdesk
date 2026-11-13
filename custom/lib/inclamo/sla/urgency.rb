# frozen_string_literal: true

module Inclamo
  module Sla
    # How pressing a conversation's SLA is: the rule of the SLA badge
    # (shims/…/inclamo/slaBadge.js), for counting on the server. The two are
    # kept the same by one list of cases both are tested on
    # (custom/spec/fixtures/sla_urgency_cases.json).
    #
    # While the first response is not reached, that target decides. After it,
    # the resolution target, and only once it is soon or overdue. "Soon" is the
    # last quarter of the target and never less than its last five minutes.
    module Urgency
      SOON_SHARE = 0.25
      SOON_FLOOR_SECONDS = 300
      LEVELS = %w[overdue soon other].freeze

      module_function

      def soon_from(target_seconds)
        [target_seconds, [target_seconds * SOON_SHARE, SOON_FLOOR_SECONDS].max].min
      end

      # `shown`: a timer as Inclamo::Sla::TimerPresenter gives it. Answers
      # [target, look] as the badge would show them, or nil for no badge.
      def of(shown)
        shown = shown&.deep_stringify_keys
        return nil if shown.nil? || shown['stopped']

        first = pressing(shown['first_response'])
        return ['first_response', first] if first

        resolution = pressing(shown['resolution'])
        resolution && resolution != 'calm' ? ['resolution', resolution] : nil
      end

      # The level a conversation is counted under: overdue, soon, or other
      # (calm, nothing to watch, no timer).
      def level(timer, now: Time.current)
        look = timer && of(TimerPresenter.new(timer, now: now).as_json)&.last
        %w[overdue soon].include?(look) ? look : 'other'
      end

      def pressing(target)
        return nil if target.nil? || target['state'] == 'stopped' || !target['took_seconds'].nil?
        return 'overdue' if target['state'] == 'missed'

        left = target['remaining_seconds'].to_f
        return 'overdue' if target['state'] == 'running' && left <= 0

        left <= soon_from(target['target_seconds']) ? 'soon' : 'calm'
      end
    end
  end
end
