# frozen_string_literal: true

module Inclamo
  module Ai
    # The two calls the helpdesk makes to the AI service: registering a
    # connection and removing it (design D3, D4; docs/ai-connector.md §1).
    #
    # Both go through Chatwoot's SSRF filter the way SafeFetch sends a webhook
    # (lib/safe_fetch/fetcher.rb): private and internal addresses are refused
    # unless SAFE_FETCH_ALLOW_PRIVATE_NETWORK is on. SafeFetch.fetch itself is
    # not used: it drops the body of an answer that is not 2xx, and a refusal's
    # body carries the message for the administrator. Redirects are not followed.
    class ServiceClient
      Registration = Data.define(:connection_id, :webhook_url)
      MAX_MESSAGE = 500
      MAX_URL = 2000

      # How host names are resolved; replaced in specs.
      def self.resolver
        SsrfFilter::DEFAULT_RESOLVER
      end

      # POST {service_url}/connections with the one-time token of the code.
      def register(code, body)
        response = request(:post, code.connections_url, token: code.token, body: body.to_json)
        status = response.code.to_i
        return registration_from(response) if status == 201
        raise refusal_from(response) if (400..499).cover?(status)

        raise Error::NotAnswered, "the AI service answered #{status}"
      end

      # DELETE {service_url}/connections/{id} with the bot's former token.
      def remove(service_url:, connection_id:, token:)
        url = "#{service_url.to_s.chomp('/')}/connections/#{ERB::Util.url_encode(connection_id.to_s)}"
        status = request(:delete, url, token: token).code.to_i
        raise Error::NotAnswered, "the AI service answered #{status}" unless (200..299).cover?(status)

        true
      end

      private

      def request(method, url, token:, body: nil)
        headers = { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' }
        headers['Content-Type'] = 'application/json' if body
        options = SafeFetch::RequestOptions.new(
          url: url, method: method, body: body, headers: headers, resolver: self.class.resolver,
          open_timeout: TIME_LIMIT, read_timeout: TIME_LIMIT, validate_content_type: false
        )
        Timeout.timeout(TIME_LIMIT) { transport(options) }
      rescue Error
        raise
      rescue StandardError, Timeout::Error => e
        # The class only: a message may name the address or echo the request.
        raise Error::NotAnswered, "the AI service did not answer: #{e.class}"
      end

      def transport(options)
        return SafeFetch::PrivateNetworkRequest.new(options).perform if Ai.private_network_allowed?

        SsrfFilter.public_send(options.method, options.url, **options.request_options, max_redirects: 0, allow_unfollowed_redirects: true)
      end

      def registration_from(response)
        data = parse(response)
        connection_id = data['connection_id']
        webhook_url = data['webhook_url'].to_s
        valid_id = (connection_id.is_a?(String) && connection_id.present? && connection_id.length <= 200) || connection_id.is_a?(Integer)
        unless valid_id && webhook_url.length <= MAX_URL && Ai.acceptable_url?(webhook_url)
          raise Error::NotAnswered.new('the AI service answered 201 without a connection id and a webhook address', connection_id: valid_id ? connection_id.to_s : nil)
        end

        Registration.new(connection_id: connection_id.to_s, webhook_url: webhook_url)
      end

      def refusal_from(response)
        data = parse(response)
        message = data['message'].is_a?(String) ? data['message'].strip.first(MAX_MESSAGE) : ''
        service_error = data['error'].is_a?(String) ? data['error'].first(100) : nil
        Error::Refused.new(message.presence || I18n.t('inclamo.ai_connection.errors.refused_without_message'), service_error: service_error)
      end

      def parse(response)
        data = JSON.parse(response.body.to_s)
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
