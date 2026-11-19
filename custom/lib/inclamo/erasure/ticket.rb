# frozen_string_literal: true

module Inclamo
  module Erasure
    # The ticket of a request about one shopper: a conversation of the
    # account's "Data requests" inbox, the way a call is a conversation of the
    # Phone inbox. The inbox is an API inbox the helpdesk makes with the
    # account's first such request; it has no members, so only the account's
    # administrators see it, and no bot, so nothing is held for the AI agent.
    # Every ticket belongs to one fixed contact of the account, never to the
    # shopper: deleting the shopper must not delete the ticket.
    #
    # A ticket is told from a shopper's conversation by its inbox, by its label
    # (LABELS) and by its request (the conversation's custom attribute
    # ATTRIBUTE names it). Its notes hold no email and no phone: those are
    # shown by the ticket's card from the request, so clearing the request
    # cleans the ticket (ShopperFinish).
    #
    # The first note and every reminder (Reminders) mention the account's
    # administrators of that moment (`addressed`), so each gets Chatwoot's
    # notification of a mention: a note of an inbox without members tells
    # nobody otherwise.
    module Ticket
      LABELS = { 'shopper_erasure' => 'inclamo_erasure_request', 'shopper_data_request' => 'inclamo_data_request' }.freeze
      LABEL_COLOR = '#8E4EC6'
      ATTRIBUTE = 'inclamo_shopper_request_id'
      # Above normal, so it stands out in the administrators' list; the ready
      # team queue "Urgent" lists urgent conversations, and a ticket enters no
      # team queue.
      PRIORITY = :high

      module_function

      # The account's inbox and contact for tickets, made when missing.
      def place!(account)
        place = Inclamo::DataRequestInbox.find_by(account_id: account.id)
        if place.nil? || !Inbox.exists?(id: place.inbox_id)
          place&.destroy!
          place = Inclamo::DataRequestInbox.create!(account: account, inbox: new_inbox(account))
        end
        place.update!(contact: new_contact(account)) unless place.contact_id && Contact.exists?(id: place.contact_id)
        place
      end

      def new_inbox(account)
        account.inboxes.create!(name: Words.t(account, 'inbox_name'), channel: Channel::Api.create!(account: account),
                                enable_auto_assignment: false)
      end

      def new_contact(account)
        account.contacts.create!(name: Words.t(account, 'contact_name'))
      end

      # The two labels, added to the account's list so the dashboard shows them.
      def labels!(account)
        LABELS.each_value do |title|
          next if account.labels.exists?(title: title)

          ActiveRecord::Base.transaction(requires_new: true) do
            account.labels.create!(title: title, description: Words.t(account, "labels.#{title}"), color: LABEL_COLOR, show_on_sidebar: false)
          end
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          next
        end
      end

      # Opens the request's ticket with its first note. Answers the conversation.
      def open!(request, account, contacts:, conversations:)
        place = place!(account)
        labels!(account)
        contact_inbox = ContactInbox.find_by(contact_id: place.contact_id, inbox_id: place.inbox_id) ||
                        ContactInbox.create!(contact_id: place.contact_id, inbox_id: place.inbox_id, source_id: SecureRandom.uuid)
        conversation = Conversation.new(
          account_id: account.id, inbox_id: place.inbox_id, contact_id: place.contact_id, contact_inbox_id: contact_inbox.id,
          status: :open, priority: PRIORITY, custom_attributes: { ATTRIBUTE => request.id }
        )
        conversation.label_list = [LABELS.fetch(request.kind)]
        conversation.save!
        note!(conversation, addressed(account, first_note(request, account, contacts, conversations)))
        request.update!(conversation_id: conversation.id)
        conversation
      end

      def first_note(request, account, contacts, conversations)
        counts = Words.counts(account, contacts, conversations)
        if request.shopper_erasure?
          Words.t(account, 'notes.erasure_made', **counts, date: Words.time(request.delete_after))
        else
          Words.t(account, 'notes.data_request_made', **counts)
        end
      end

      # The note's text after a line that mentions every administrator the
      # account has now, never an agent. Chatwoot's mention service notifies
      # each of them (in the dashboard, and by mail where they chose that and
      # the installation sends mail) and lists the ticket among their
      # mentions. The line names the administrators only.
      def addressed(account, text)
        line = account.administrators.reorder('users.id').map { |user| mention(user) }.join(' ')
        line.empty? ? text : "#{line}\n\n#{text}"
      end

      # A person as Chatwoot's own editor mentions one:
      # [@Name](mention://user/<id>/<the name, URL-encoded>). Brackets and
      # parentheses would end the markup early, so the name shown leaves them out.
      def mention(user)
        name = user.available_name.to_s.gsub(/[\[\]()]/, '').squish.presence || "##{user.id}"
        "[@#{name}](mention://user/#{user.id}/#{ERB::Util.url_encode(name)})"
      end

      # A private note of the ticket; `author` is the administrator who acted,
      # none for the helpdesk's own notes.
      def note!(conversation, text, author: nil)
        conversation.messages.create!(
          account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, content_type: :text,
          private: true, content: text, sender: author
        )
      end

      def resolve!(conversation)
        conversation.update!(status: :resolved) unless conversation.resolved?
      end

      # Runs what changes a ticket on a request's behalf. Chatwoot writes a line
      # of its own when a conversation's status changes, and without a person
      # signed in it says the conversation was resolved "due to inactivity";
      # the ticket's own notes say who did what and why, so a status the
      # helpdesk changes here writes no such line (Chatwoot writes none for a
      # change it is told was made by something other than an automation rule
      # or a contact). Wraps the whole transaction: the line would be written
      # when it commits.
      def acting(request)
        previous = Current.executed_by
        Current.executed_by = request
        yield
      ensure
        Current.executed_by = previous
      end

      def reopen!(conversation)
        conversation.update!(status: :open) unless conversation.open?
      end

      # The ticket of a request, while it exists.
      def conversation_of(request)
        request.conversation_id && Conversation.find_by(id: request.conversation_id, account_id: request.account_id)
      end
    end
  end
end
