# frozen_string_literal: true

require 'net/http'

module Inclamo
  module Shopify
    # Sends one GraphQL document to one shop and returns the `data` of the
    # answer. Throttled requests are retried with the wait the store states,
    # inside the time limit; nothing else is retried, because a request that
    # timed out may have been executed.
    class Client
      DEFAULT_TIME_LIMIT = 10 # seconds for the whole call, waits included
      THROTTLED = 'THROTTLED'

      def initialize(domain:, access_token:, time_limit: DEFAULT_TIME_LIMIT, sleeper: ->(seconds) { sleep(seconds) })
        raise ArgumentError, "not a Shopify domain: #{domain.inspect}" unless Shopify.valid_domain?(domain)

        @domain = domain
        @access_token = access_token
        @time_limit = time_limit
        @sleeper = sleeper
      end

      def query(document_name, variables = {})
        body = { query: Documents.fetch(document_name), variables: variables }.to_json
        deadline = now + @time_limit

        loop do
          response = post(body, deadline)
          wait = throttle_wait(response)
          return data_of(response) if wait.nil?
          raise Error::Throttled, 'the store kept throttling until the time limit' if now + wait >= deadline

          @sleeper.call(wait)
        end
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def uri
        @uri ||= URI.join(Shopify.base_url(@domain), "/admin/api/#{API_VERSION}/graphql.json")
      end

      def post(body, deadline)
        remaining = deadline - now
        raise Error::Timeout, 'the store did not answer within the time limit' if remaining <= 0

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = remaining
        http.read_timeout = remaining
        http.write_timeout = remaining
        http.request(request_for(body))
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
        raise Error::Timeout, 'the store did not answer within the time limit'
      rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError => e
        raise Error::Unavailable, "could not reach the store: #{e.class}"
      end

      def request_for(body)
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request['X-Shopify-Access-Token'] = @access_token
        # The shop is always named, also when a proxy stands in front of it.
        request['X-Shopify-Shop-Domain'] = @domain
        request.body = body
        request
      end

      # Seconds to wait when the store throttled the request, nil otherwise.
      def throttle_wait(response)
        return [response['Retry-After'].to_f, 1.0].max if response.code == '429'
        return unless response.code == '200'

        payload = parse(response)
        return unless error_codes(payload).include?(THROTTLED)

        cost = payload.dig('extensions', 'cost') || {}
        status = cost['throttleStatus'] || {}
        missing = cost['requestedQueryCost'].to_f - status['currentlyAvailable'].to_f
        rate = status['restoreRate'].to_f
        missing.positive? && rate.positive? ? (missing / rate).ceil.to_f : 1.0
      end

      def data_of(response)
        raise_for_status(response)
        payload = parse(response)
        codes = error_codes(payload)
        if payload['errors'].present?
          messages = Array(payload['errors']).map { |error| error.is_a?(Hash) ? error['message'] : error.to_s }
          raise Error::QueryError.new(messages.join('; '), codes: codes)
        end

        payload['data'] || {}
      end

      def raise_for_status(response)
        case response.code.to_i
        when 200 then nil
        when 401, 403 then raise Error::Unauthorized, 'the store refused the access token'
        when 402, 404, 423 then raise Error::ShopUnavailable, "the store answered #{response.code}"
        else raise Error::Unavailable, "the store answered #{response.code}"
        end
      end

      def parse(response)
        @parsed ||= {}.compare_by_identity
        @parsed[response] ||= JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise Error::Unavailable, 'the store sent an answer that is not JSON'
      end

      def error_codes(payload)
        Array(payload['errors']).filter_map { |error| error.dig('extensions', 'code') if error.is_a?(Hash) }
      end
    end
  end
end
