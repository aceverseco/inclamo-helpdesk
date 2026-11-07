# frozen_string_literal: true

require 'net/http'

module Inclamo
  module Shopify
    # One POST with a time limit, and transport failures turned into our errors.
    # A failure while connecting means the request was never sent; a failure
    # once it is on its way leaves open whether the store acted on it.
    module Http
      def self.post(uri, headers:, body:, time_limit:)
        raise Error::Timeout, 'the store did not answer within the time limit' if time_limit <= 0

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = time_limit
        http.read_timeout = time_limit
        http.write_timeout = time_limit
        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |name, value| request[name] = value }
        request.body = body
        connect(http)
        begin
          http.request(request)
        rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
          raise Error::Timeout, 'the store did not answer within the time limit'
        rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError => e
          raise Error::Unavailable, "could not reach the store: #{e.class}"
        ensure
          http.finish if http.started?
        end
      end

      def self.connect(http)
        http.start
      rescue Net::OpenTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError => e
        raise Error::Unreachable, "could not reach the store: #{e.class}"
      end
      private_class_method :connect
    end
  end
end
