# frozen_string_literal: true

module Inclamo
  module Ai
    module Calls
      # The call's fields on its conversation: custom attributes the call card
      # reads. They are defined in the account when the AI agent is connected
      # (and with a call, for an account connected before they existed), so
      # Chatwoot's filters and automation rules can use them; a definition the
      # account already has under the same key is kept as it is.
      module Attributes
        DEFINITIONS = {
          'inclamo_call_entry' => ['Call: entry', :text, 'inbound, outbound or web'],
          'inclamo_call_line' => ['Call: shop line', :text, "The shop's number the call came to or went from"],
          'inclamo_call_caller' => ['Call: caller number', :text, "The caller's number, when the call had one"],
          'inclamo_call_duration' => ['Call: duration, s', :number, 'The length of the call in seconds'],
          'inclamo_call_ended_at' => ['Call: ended at', :date, 'When the call ended'],
          'inclamo_call_outcome' => ['Call: outcome', :text, 'How the AI agent ended the call'],
          'inclamo_call_matched_by' => ['Call: contact found by', :text, 'phone, email, created, anonymous or ambiguous'],
          'inclamo_call_recording' => ['Call: recording', :link, 'A link to the recording, when the AI service sent one']
        }.freeze

        module_function

        def define!(account)
          existing = account.custom_attribute_definitions.conversation_attribute.where(attribute_key: DEFINITIONS.keys).pluck(:attribute_key)
          DEFINITIONS.except(*existing).each do |key, (name, type, description)|
            # In a savepoint: defined at the same moment by another request, it exists.
            ActiveRecord::Base.transaction(requires_new: true) do
              account.custom_attribute_definitions.create!(
                attribute_key: key, attribute_model: :conversation_attribute, attribute_display_name: name,
                attribute_display_type: type, attribute_description: description
              )
            end
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
            next
          end
        end

        def of(filing, matched_by)
          {
            'inclamo_call_entry' => filing.entry,
            'inclamo_call_line' => filing.line,
            'inclamo_call_caller' => filing.phone,
            'inclamo_call_duration' => filing.duration,
            'inclamo_call_ended_at' => filing.ended_at.utc.iso8601,
            'inclamo_call_outcome' => filing.outcome,
            'inclamo_call_matched_by' => matched_by,
            'inclamo_call_recording' => filing.recording_url
          }.compact
        end
      end
    end
  end
end
