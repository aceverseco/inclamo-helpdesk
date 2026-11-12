# frozen_string_literal: true

module Inclamo
  module Ai
    module Calls
      # Removes payment card numbers from a call's text before it is stored:
      # 13 to 19 digits, single spaces or dashes allowed between them, that
      # pass the Luhn check. A run of digit groups that is no card number as a
      # whole is searched for one made of whole groups, so a card number
      # followed by its security code is still removed.
      module CardNumbers
        PLACEHOLDER = '[card number removed]'
        RUN = /(?<!\d)\d(?:[ -]?\d)*(?!\d)/
        LENGTHS = (13..19)

        module_function

        def mask(text)
          return text unless text.is_a?(String)

          text.gsub(RUN) { |run| mask_run(run) }
        end

        def mask_run(run)
          return run if run.count('0-9') < LENGTHS.min

          # Groups of digits and the separators between them, in turn.
          parts = run.split(/([ -])/)
          groups = parts.each_slice(2).map(&:first)
          result = +''
          index = 0
          while index < groups.size
            last = card_end(groups, index)
            if last
              result << PLACEHOLDER
              index = last + 1
            else
              result << groups[index]
              index += 1
            end
            result << parts[(index * 2) - 1] if index < groups.size
          end
          result
        end

        # The last group of the longest card number that starts at group `first`.
        def card_end(groups, first)
          (groups.size - 1).downto(first).find do |last|
            digits = groups[first..last].join
            LENGTHS.cover?(digits.length) && luhn?(digits)
          end
        end

        def luhn?(digits)
          sum = digits.reverse.each_char.with_index.sum do |char, position|
            value = char.to_i
            next value if position.even?

            value *= 2
            value > 9 ? value - 9 : value
          end
          (sum % 10).zero?
        end
      end
    end
  end
end
