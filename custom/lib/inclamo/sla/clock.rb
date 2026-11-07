# frozen_string_literal: true

module Inclamo
  module Sla
    # The time a timer has counted (design D3). Plain time, or, for a policy
    # that counts business hours only, the overlap with the business hours of
    # the conversation's inbox in the inbox's time zone. An inbox without
    # business hours counts at all times. Nothing ticks: elapsed time and
    # deadlines are computed from the moments stored on the timer.
    class Clock
      # A deadline further than this is "never".
      HORIZON_DAYS = 3_660

      def initialize(inbox:, business_hours_only:)
        @plain = !business_hours_only || inbox.nil? || !inbox.working_hours_enabled?
        return if @plain

        @zone = ActiveSupport::TimeZone[inbox.timezone.to_s] || ActiveSupport::TimeZone['UTC']
        @days = inbox.working_hours.to_a.index_by(&:day_of_week)
        @never_open = (0..6).none? { |wday| day_open?(@days[wday]) }
      end

      def plain?
        @plain
      end

      # Whole seconds counted between two moments.
      def elapsed(from, to)
        return 0 if to <= from
        return (to - from).floor if plain?

        total = 0
        each_open_interval(from, to) { |open, close| total += [close, to].min - [open, from].max }
        total.floor
      end

      # The moment `seconds` have been counted from `from`; nil when the
      # business hours never open.
      def deadline(from, seconds)
        return from + seconds if plain?

        left = seconds
        each_open_interval(from, nil) do |open, close|
          start = [open, from].max
          return start + left if left <= close - start

          left -= close - start
        end
        nil
      end

      # Is the clock counting at this moment? False outside business hours.
      def counting_at?(time)
        return true if plain?

        intervals(local_date(time)).any? { |open, close| time >= open && time < close }
      end

      # The next moment after `time` when counting starts or stops; nil for
      # plain time and for hours that never open.
      def next_change(time)
        return nil if plain?

        each_open_interval(time, nil) { |open, close| return open > time ? open : close }
        nil
      end

      private

      # Business-hours intervals that end after `from` (and start before `to`,
      # when given), in order.
      def each_open_interval(from, to)
        return if @never_open

        date = local_date(from)
        last = to && local_date(to)
        HORIZON_DAYS.times do
          break if last && date > last

          intervals(date).each do |open, close|
            next if close <= from
            return if to && open >= to

            yield open, close
          end
          date += 1
        end
      end

      # The day's business hours as [open, close) moments; an "open all day"
      # day runs from midnight to midnight, so it is 23 or 25 hours long on the
      # day the clocks change.
      def intervals(date)
        day = @days[date.wday]
        return [] unless day_open?(day)
        return [[at(date, 0, 0), at(date + 1, 0, 0)]] if day.open_all_day?

        [[at(date, day.open_hour, day.open_minutes), at(date, day.close_hour, day.close_minutes)]]
      end

      def day_open?(day)
        return false if day.nil? || day.closed_all_day?
        return true if day.open_all_day?

        day.open_hour.present? && day.close_hour.present? &&
          (day.close_hour * 60) + day.close_minutes.to_i > (day.open_hour * 60) + day.open_minutes.to_i
      end

      def at(date, hour, minute)
        @zone.local(date.year, date.month, date.day, hour, minute)
      end

      def local_date(time)
        time.in_time_zone(@zone).to_date
      end
    end
  end
end
