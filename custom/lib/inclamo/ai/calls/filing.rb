# frozen_string_literal: true

module Inclamo
  module Ai
    module Calls
      # One filing as the AI service sent it, checked against the rules of
      # docs/ai-connector-calls.md and with card numbers removed. Raises
      # Refused with the contract's code for a body that breaks a rule.
      class Filing
        Turn = Struct.new(:role, :text, :at, keyword_init: true)

        attr_reader :call_id, :entry, :line, :phone, :email, :name, :ended_at, :duration, :outcome,
                    :needs_team, :priority, :labels, :recording_url, :turns, :record

        def self.read(body)
          new(body).tap(&:read)
        end

        def initialize(body)
          @body = body.is_a?(Hash) ? body.with_indifferent_access : {}
        end

        def read
          read_call
          read_caller
          read_outcome
          read_labels
          read_turns
          read_record
          self
        end

        # The only part of a filing that may reach the log.
        def counts
          { turns: turns.size, labels: labels.size }
        end

        private

        def invalid!
          raise Refused, :invalid_call
        end

        def too_large!
          raise Refused, :too_large
        end

        def text(value, max: nil)
          return nil if value.nil? || value == ''

          invalid! unless value.is_a?(String)
          invalid! if max && value.length > max
          value
        end

        def time(value)
          invalid! unless value.is_a?(String)
          Time.iso8601(value)
        rescue ArgumentError
          invalid!
        end

        def number(value)
          value = text(value)
          invalid! if value && !E164.match?(value)
          value
        end

        def read_call
          @call_id = @body[:call_id]
          invalid! unless @call_id.is_a?(String) && CALL_ID_FORMAT.match?(@call_id)
          @entry = @body[:entry]
          invalid! unless ENTRIES.include?(@entry)
          @line = number(@body[:line])
          @ended_at = time(@body[:ended_at])
          @duration = @body[:duration]
          invalid! unless @duration.nil? || (@duration.is_a?(Integer) && @duration >= 0)
          @recording_url = text(@body[:recording_url], max: MAX_URL_LENGTH)
          invalid! if @recording_url && !https?(@recording_url)
        end

        def read_caller
          caller = @body[:caller]
          caller = {} if caller.nil?
          invalid! unless caller.is_a?(Hash)
          caller = caller.with_indifferent_access
          @phone = number(caller[:phone])
          @email = text(caller[:email], max: MAX_NAME_LENGTH)&.strip
          invalid! if @email && !Devise.email_regexp.match?(@email)
          @name = CardNumbers.mask(text(caller[:name], max: MAX_NAME_LENGTH)&.strip).presence
        end

        def read_outcome
          @outcome = @body[:outcome]
          invalid! unless @outcome.is_a?(String) && OUTCOME_FORMAT.match?(@outcome)
          @needs_team = @body[:needs_team]
          invalid! unless [true, false].include?(@needs_team)
          @priority = text(@body[:priority])
          invalid! if @priority && PRIORITIES.exclude?(@priority)
        end

        def read_labels
          labels = @body[:labels] || []
          invalid! unless labels.is_a?(Array) && labels.size <= MAX_LABELS
          raise Refused, :invalid_label unless labels.all? { |label| label.is_a?(String) && label.length <= LABEL_MAX_LENGTH && LABEL_FORMAT.match?(label) }

          @labels = labels.uniq
        end

        def read_turns
          turns = @body[:turns] || []
          invalid! unless turns.is_a?(Array)
          too_large! if turns.size > MAX_TURNS
          @turns = turns.map { |turn| read_turn(turn) }
        end

        def read_turn(turn)
          invalid! unless turn.is_a?(Hash)
          turn = turn.with_indifferent_access
          invalid! unless ROLES.include?(turn[:role]) && turn[:text].is_a?(String) && turn[:text].present?
          too_large! if turn[:text].length > MAX_TURN_LENGTH
          Turn.new(role: turn[:role], text: CardNumbers.mask(turn[:text]), at: turn[:at].nil? ? nil : time(turn[:at]))
        end

        def read_record
          record = @body[:record]
          invalid! unless record.is_a?(String) && record.present?
          too_large! if record.length > MAX_RECORD_LENGTH
          @record = CardNumbers.mask(record)
        end

        def https?(value)
          uri = URI.parse(value)
          uri.is_a?(URI::HTTPS) && uri.host.present?
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
