# frozen_string_literal: true

module Inclamo
  module Ai
    # What the agent reads of a conversation (design D6): its state and its
    # last public messages, oldest first, with their files, and the number of
    # files the shopper sent in all of it. Private notes, activity messages and
    # Chatwoot's own template messages are left out.
    class History
      DEFAULT_LIMIT = 30
      MAX_LIMIT = 100

      def initialize(conversation, connection, limit: nil)
        @conversation = conversation
        @connection = connection
        @limit = limit.to_i.positive? ? [limit.to_i, MAX_LIMIT].min : DEFAULT_LIMIT
      end

      def as_json(*)
        {
          id: @conversation.display_id,
          status: @conversation.status,
          inbox_id: @conversation.inbox_id,
          priority: @conversation.priority,
          labels: @conversation.label_list.to_a,
          shopper_files: Attachment.where(message_id: public_messages.incoming.select(:id)).count,
          messages: recent.map { |message| present(message) }
        }
      end

      private

      def public_messages
        @conversation.messages.where(message_type: %i[incoming outgoing], private: false)
      end

      def recent
        public_messages.includes(:sender, attachments: { file_attachment: :blob })
                       .reorder(created_at: :desc, id: :desc).limit(@limit).to_a.reverse
      end

      def present(message)
        {
          id: message.id,
          created_at: message.created_at.utc.iso8601,
          role: role(message),
          text: message.content.to_s,
          files: message.attachments.sort_by(&:id).map { |attachment| file(attachment) }
        }
      end

      def role(message)
        return 'shopper' if message.incoming?
        return 'agent' if @connection.agent_bot?(message.sender)

        'team'
      end

      def file(attachment)
        attached = attachment.file.attached?
        {
          id: attachment.id,
          file_type: attachment.file_type,
          content_type: attached ? attachment.file.content_type : nil,
          file_size: attached ? attachment.file.byte_size : nil,
          url: attached ? attachment.file_url : attachment.external_url
        }
      end
    end
  end
end
