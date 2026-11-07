# frozen_string_literal: true

module Inclamo
  # SLA timers (capability sla-timers): policies, the timer of a conversation,
  # the clock and the periodic check for missed targets.
  module Sla
    # The label a conversation gets when a target is missed (design D6).
    LABEL = 'sla-missed'
    LABEL_COLOR = '#E5484D'
    DEFAULT_CHECK_SECONDS = 60
    # The steps that divide a minute (and an hour) evenly: the only ones a cron
    # line repeats at an even pace.
    EVEN_STEPS = [30, 20, 15, 12, 10, 6, 5, 4, 3, 2, 1].freeze
    # The units of a target in the note, as on the policies page.
    DURATION_UNITS = { day: 86_400, hour: 3600, minute: 60, second: 1 }.freeze

    # How often the periodic check runs (design D4): INCLAMO_SLA_CHECK_SECONDS,
    # 60 by default. The end-to-end stack sets a few seconds.
    def self.check_seconds
      value = Integer(ENV.fetch('INCLAMO_SLA_CHECK_SECONDS', DEFAULT_CHECK_SECONDS), exception: false)
      value&.positive? ? even_interval(value) : DEFAULT_CHECK_SECONDS
    end

    # The interval taken down to one a cron line repeats evenly: below a minute
    # a step that divides the minute, above it whole minutes that divide the
    # hour, and an hour at most.
    def self.even_interval(seconds)
      return EVEN_STEPS.find { |step| step <= seconds } if seconds < 60
      return 3600 if seconds >= 3600

      EVEN_STEPS.find { |step| step <= seconds / 60 } * 60
    end

    # The interval as a sidekiq-cron line: with seconds below a minute, in
    # whole minutes above, hourly at most.
    def self.check_cron(seconds = check_seconds)
      seconds = even_interval(seconds)
      return "*/#{seconds} * * * * *" if seconds < 60
      return '0 * * * *' if seconds == 3600

      minutes = seconds / 60
      minutes == 1 ? '* * * * *' : "*/#{minutes} * * * *"
    end

    # A length of time in words, for the note, in days, hours, minutes and
    # seconds: "2 hours", "30 days", "1 day and 4 hours".
    def self.duration_words(seconds)
      left = seconds.to_i
      words = DURATION_UNITS.filter_map do |unit, size|
        count, left = left.divmod(size)
        I18n.t("inclamo.sla.units.#{unit}", count: count) if count.positive?
      end
      words.empty? ? I18n.t('inclamo.sla.units.second', count: 0) : words.to_sentence
    end
  end
end
