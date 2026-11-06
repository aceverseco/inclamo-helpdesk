# frozen_string_literal: true

module Inclamo
  # SLA timers (capability sla-timers): policies, the timer of a conversation,
  # the clock and the periodic check for missed targets.
  module Sla
    # The label a conversation gets when a target is missed (design D6).
    LABEL = 'sla-missed'
    LABEL_COLOR = '#E5484D'
    DEFAULT_CHECK_SECONDS = 60

    # How often the periodic check runs (design D4): INCLAMO_SLA_CHECK_SECONDS,
    # 60 by default. The end-to-end stack sets a few seconds.
    def self.check_seconds
      value = Integer(ENV.fetch('INCLAMO_SLA_CHECK_SECONDS', DEFAULT_CHECK_SECONDS), exception: false)
      value&.positive? ? value : DEFAULT_CHECK_SECONDS
    end

    # The interval as a sidekiq-cron line: with seconds below a minute,
    # in whole minutes above.
    def self.check_cron(seconds = check_seconds)
      return "*/#{seconds} * * * * *" if seconds < 60

      minutes = (seconds / 60).clamp(1, 59)
      minutes == 1 ? '* * * * *' : "*/#{minutes} * * * *"
    end

    # A length of time in words, for the note: "2 hours", "1 day and 4 hours".
    def self.duration_words(seconds)
      ActiveSupport::Duration.build(seconds.to_i).inspect
    end
  end
end
