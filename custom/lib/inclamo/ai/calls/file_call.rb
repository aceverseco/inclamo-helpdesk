# frozen_string_literal: true

module Inclamo
  module Ai
    module Calls
      # Files one finished call as a conversation of the Phone inbox, in one
      # transaction: the call's key, the contact, the conversation with its
      # status, priority, labels and attributes, the turns as messages, the
      # record as a private note written last.
      #
      # The turns are written as rows, without Chatwoot's message callbacks
      # (app/models/message.rb:141, :333-342). With them every turn would queue
      # a notification for the assignee and a send job, an incoming turn would
      # reopen a resolved call, and the merchant's rules would run once per
      # turn. The conversation and the note go through Chatwoot's models, so a
      # call gives the events a chat's conversation and a note give.
      class FileCall
        Result = Struct.new(:conversation, :contact_id, :found, :matched_by, :labels_added, keyword_init: true)

        TURN_GAP = 0.001

        def self.call(...)
          new(...).call
        end

        def initialize(account:, connection:, bot:, filing:)
          @account = account
          @connection = connection
          @bot = bot
          @filing = filing
          @inbox = connection.phone_inbox
        end

        def call
          earlier || file
        rescue ActiveRecord::RecordNotUnique
          # The same call was filed at the same moment: its transaction won.
          earlier || raise
        end

        private

        def earlier
          key = Inclamo::CallConversation.find_by(account_id: @account.id, call_id: @filing.call_id)
          return unless key&.conversation

          Result.new(conversation: key.conversation, contact_id: key.contact_id, found: true, matched_by: key.matched_by, labels_added: [])
        end

        def file
          ActiveRecord::Base.transaction do
            # First, so a filing of the same call at the same moment waits here
            # and then fails before it has made anything.
            key = Inclamo::CallConversation.create!(account_id: @account.id, call_id: @filing.call_id, created_at: Time.current)
            Attributes.define!(@account)
            match = ContactRule.new(@account, @filing).call
            labels = labels_for(match)
            added = add_account_labels(labels)
            conversation = create_conversation(match, labels)
            last_turn_at = write_turns(conversation, match.contact)
            write_record(conversation, last_turn_at)
            key.update!(conversation_id: conversation.id, contact_id: match.contact.id, matched_by: match.matched_by)
            Result.new(conversation: conversation, contact_id: match.contact.id, found: false, matched_by: match.matched_by, labels_added: added)
          end
        end

        def labels_for(match)
          labels = @filing.labels.dup
          labels |= [AMBIGUOUS_LABEL] if match.matched_by == 'ambiguous'
          labels |= [NO_CALLER_ID_LABEL] if match.matched_by == 'anonymous'
          labels
        end

        # Labels the account does not list yet are added to its list, so the
        # dashboard shows them. Answers the titles added by this filing.
        def add_account_labels(labels)
          missing = labels - @account.labels.where(title: labels).pluck(:title)
          missing.select do |title|
            description = LABELS[title] || ADDED_LABEL_DESCRIPTION
            # In a savepoint: made at the same moment by another request, the
            # label exists and the call's transaction goes on.
            ActiveRecord::Base.transaction(requires_new: true) do
              @account.labels.create!(title: title, description: description, color: LABEL_COLOR, show_on_sidebar: false)
            end
            true
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
            false
          end
        end

        def create_conversation(match, labels)
          contact_inbox = ContactInbox.find_by(contact_id: match.contact.id, inbox_id: @inbox.id) ||
                          ContactInbox.create!(contact_id: match.contact.id, inbox_id: @inbox.id, source_id: SecureRandom.uuid)
          conversation = Conversation.new(
            account_id: @account.id, inbox_id: @inbox.id, contact_id: match.contact.id, contact_inbox_id: contact_inbox.id,
            status: @filing.needs_team ? :open : :resolved, priority: @filing.priority,
            custom_attributes: Attributes.of(@filing, match.matched_by)
          )
          conversation.label_list = labels
          conversation.save!
          conversation
        end

        # Answers the time of the last turn, or nil for a call without turns.
        def write_turns(conversation, contact)
          return if @filing.turns.empty?

          times = turn_times
          rows = @filing.turns.each_with_index.map do |turn, index|
            caller = turn.role == 'caller'
            {
              account_id: @account.id, inbox_id: @inbox.id, conversation_id: conversation.id,
              message_type: Message.message_types[caller ? 'incoming' : 'outgoing'], content_type: Message.content_types['text'],
              status: Message.statuses['sent'], private: false,
              content: turn.text, processed_message_content: turn.text,
              sender_type: caller ? 'Contact' : 'AgentBot', sender_id: caller ? contact.id : @bot.id,
              created_at: times[index], updated_at: times[index]
            }
          end
          # insert_all casts by column, not by the model's enums: the types above are their numbers.
          Message.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations
          times.last
        end

        # The times the turns were spoken, when the AI service sent every one;
        # otherwise one second apart, the last at the call's end. Always in the
        # call's order: a turn not later than the one before it is put just after it.
        def turn_times
          turns = @filing.turns
          given = turns.all?(&:at)
          times = turns.each_with_index.map { |turn, index| given ? turn.at : @filing.ended_at - (turns.size - 1 - index) }
          times.each_with_index do |time, index|
            times[index] = times[index - 1] + TURN_GAP if index.positive? && time <= times[index - 1]
          end
          times
        end

        # The record goes through Chatwoot's model, as a note of the AI agent:
        # the last message of the call, whatever the AI service's clock says.
        def write_record(conversation, last_turn_at)
          now = Time.current
          at = last_turn_at && last_turn_at >= now ? last_turn_at + TURN_GAP : now
          note = conversation.messages.new(
            account_id: @account.id, inbox_id: @inbox.id, message_type: :outgoing, content_type: :text, private: true,
            content: @filing.record, sender: @bot, created_at: at, updated_at: at
          )
          # Without validations: Chatwoot's guard against message loops counts the
          # conversation's messages of the last minute (app/models/message.rb,
          # prevent_message_flooding), which the turns of a call just ended are.
          # The record's length is checked by Filing.
          note.save!(validate: false)
          note
        end
      end
    end
  end
end
