# frozen_string_literal: true

module Inclamo
  module Shopify
    # What is done to a new conversation before Chatwoot evaluates its
    # automation rules: the store's facts about the customer are written, and
    # the order named in the customer's first message is tied, so a rule can
    # use the facts as conditions and the order variables in its message.
    #
    # It runs inside the background job that carries the event to every
    # listener, so it never raises and has one time limit for all its store
    # calls. Its writes are quiet: they start no evaluation of rules themselves.
    class BeforeRules
      TIME_LIMIT = 5 # seconds for all the store calls of one event

      # Reads like an OrderReader; every call gets what is left of one time limit.
      class Reader
        READS = %i[customers_by_email customers_by_phone customer_with_orders order order_by_number].freeze

        def initialize(record, seconds)
          @record = record
          @deadline = now + seconds
        end

        READS.each do |name|
          define_method(name) do |*arguments, **options|
            OrderReader.new(@record, time_limit: [@deadline - now, 0].max).public_send(name, *arguments, **options)
          end
        end

        private

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      def self.call(conversation, message: nil)
        record = ShopifyConnection.find_by(account_id: conversation.account_id)
        return unless record&.working?

        reader = Reader.new(record, TIME_LIMIT)
        CustomerFacts.new(conversation).refresh!(reader: reader, quiet: true)
        text = (message || first_message_of(conversation))&.content
        ConversationOrder.new(conversation).auto_mark!(text, reader: reader, quiet: true) if text.present?
      rescue Error => e
        # The store was silent or refused us: the rules run without the facts.
        Rails.logger.info("[inclamo] conversation #{conversation.id} goes to the automation rules without store facts: #{e.class.name}")
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
      end

      # Is this the first message the customer wrote in its conversation?
      def self.first_from_customer?(message)
        message.incoming? && !message.conversation.messages.incoming.exists?(['messages.id < ?', message.id])
      end

      def self.first_message_of(conversation)
        conversation.messages.incoming.order(:id).first
      end
      private_class_method :first_message_of
    end
  end
end
