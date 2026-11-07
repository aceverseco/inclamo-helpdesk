# frozen_string_literal: true

module Inclamo
  module Ai
    # Prepended to Chatwoot's webhook sender (Webhooks::Trigger, lib/webhooks/
    # trigger.rb) by custom/config/overlay.rb. For an agent-bot delivery to the
    # address of an account's AI connection it records success or the kind of
    # failure (design D8). The kind is an HTTP status or an error class, never
    # a body or a message. Recording never changes what the delivery does.
    module DeliveryRecorder
      def self.record(webhook_type, url, payload, error)
        return unless webhook_type.to_s == 'agent_bot_webhook'

        connection = connection_for(payload, url)
        return unless connection

        if error
          Inclamo::AiConnection.record_failure(connection.id, kind_of(error))
        else
          Inclamo::AiConnection.record_delivery(connection.id)
        end
      rescue StandardError => e
        Rails.logger.warn("[inclamo] an AI delivery could not be recorded: #{e.class}")
      end

      def self.connection_for(payload, url)
        account = payload.is_a?(Hash) ? (payload[:account] || payload['account']) : nil
        account_id = account.is_a?(Hash) ? (account[:id] || account['id']) : nil
        return if account_id.blank?

        connection = Inclamo::AiConnection.active_for(account_id)
        return unless connection&.agent_bot_id

        connection if AgentBot.where(id: connection.agent_bot_id).pick(:outgoing_url) == url
      end

      def self.kind_of(error)
        case error
        when SafeFetch::HttpError then "http_#{error.message.to_s[/\A(\d{3})\b/, 1] || 'error'}"
        when SafeFetch::FetchError then error.message.to_s.match?(/timeout|timed out|execution expired/i) ? 'timeout' : 'connection_failed'
        when SafeFetch::UnsafeUrlError then 'unsafe_address'
        when SafeFetch::InvalidUrlError then 'invalid_address'
        else error.class.name.demodulize.underscore
        end
      end

      private

      def perform_request
        result = super
        DeliveryRecorder.record(@webhook_type, @url, @payload, nil)
        result
      rescue StandardError => e
        DeliveryRecorder.record(@webhook_type, @url, @payload, e)
        raise
      end
    end
  end
end
