# frozen_string_literal: true

module Inclamo
  module Shopify
    # A short-lived key to the store of an account the store app provisioned,
    # asked of the app (capability app-store-access, contract in
    # docs/app-store-access.md):
    #
    #   POST {app address}/stores/{shop_domain}/store-key
    #   { "contract": 1, "account_id": 42, "scopes": [...] }
    #
    # signed as the app signs its provisioning calls, with the same secret
    # (Provisioning::Signature over the path as sent, the app's prefix
    # included). The app's address is the one it gave for the store when it
    # provisioned it, else the one the operator configured (INCLAMO_APP_URL).
    #
    # Sent through Chatwoot's SSRF filter, waiting at most 10 seconds, without
    # following a redirect. Returns a Grant that has passed the checks of a
    # key (the account's store, at least two minutes of life, a scope list),
    # or raises:
    #   Error::AppKeyRefused         the app says the store does not have it
    #                                (reason app_removed) or that the account is
    #                                not the one it provisioned (account_mismatch)
    #   Error::OtherStoreKey         a key to another store
    #   Error::StoreDataUnavailable  no key for any other reason: no answer, a
    #                                refusal for now (503, 401, 422, 429), a
    #                                redirect, an answer that does not read, a
    #                                key about to end
    #
    # Every request is recorded (Inclamo::ProvisioningEvent) with its account,
    # store and outcome, and logged with its status, code and duration; never
    # with a body, a key or a signature. A 401 means the two sides disagree on
    # the secret: it is also reported to the operator (ChatwootExceptionTracker,
    # which logs it as an error and sends it to Sentry where one is set up).
    class AppKey
      TIME_LIMIT = 10
      # A key with less life than this is not taken.
      MIN_LIFE = 2.minutes
      ADDRESS_VARIABLE = 'INCLAMO_APP_URL'
      # How long a connection waits after an attempt before it asks again on
      # its own (StoreConnection), unless the app asked for longer.
      PAUSE_VARIABLE = 'INCLAMO_APP_KEY_PAUSE'
      PAUSE = 30
      MAX_PAUSE = 600
      MAX_ANSWER = 64 * 1024
      CODE = /\A[a-z0-9_]{1,40}\z/
      # The app's refusals that break the connection, with the reason kept.
      BREAKING = { [404, 'store_not_installed'] => 'app_removed', [403, 'account_mismatch'] => 'account_mismatch' }.freeze

      # The key as the helpdesk takes it. Its inspection names no key.
      Grant = Data.define(:shop_domain, :access_token, :expires_at, :scopes) do
        def inspect
          "#<#{self.class.name} #{shop_domain} until #{expires_at&.utc&.iso8601} #{scopes.join(',')}>"
        end
        alias_method :to_s, :inspect
      end

      # Raised to the operator when the app refuses the signature.
      class SecretRefused < StandardError; end

      class << self
        # The scopes the helpdesk can use, and so asks for: the read scopes,
        # every action's scopes and the refund's restock scopes, read from
        # where each is declared, so a new action's scope is asked for too.
        def scopes
          (ShopifyConnection::READ_SCOPES + ShopifyConnection::ACTION_SCOPES.values.flatten + Actions::Refund::RESTOCK_SCOPES).uniq.freeze
        end

        # Where this store's keys are asked for, or nil: the address the app
        # gave for the store (docs/app-provisioning.md §3.1), else the
        # installation's. HTTPS (HTTP only where Chatwoot may reach private
        # networks: a test stack), in one spelling, without a trailing slash.
        def address(row)
          [row&.store_access_url, ENV.fetch(ADDRESS_VARIABLE, nil)].each do |value|
            address = Provisioning::AgentServices.normalize(value)
            return address if address
          end
          nil
        end

        # Whether a store's connection can be made through the app on this
        # installation: the shared secret, an address of the app and
        # encryption keys for the key.
        def available?(row)
          Provisioning.enabled? && Chatwoot.encryption_configured? && address(row).present?
        end

        def pause_seconds(retry_after = nil)
          configured = Integer(ENV.fetch(PAUSE_VARIABLE, '').strip, 10, exception: false)
          base = configured&.positive? ? configured : PAUSE
          [[base, retry_after.to_i].max, MAX_PAUSE].min
        end

        # How host names are resolved; replaced in specs.
        def resolver
          SsrfFilter::DEFAULT_RESOLVER
        end

        def call(row:, account_id:, **)
          new(row: row, account_id: account_id, **).call
        end
      end

      def initialize(row:, account_id:, time_limit: TIME_LIMIT, scopes: self.class.scopes,
                     request_id: SecureRandom.uuid, timestamp: Time.now.to_i)
        @row = row
        @account_id = account_id
        @time_limit = [time_limit.to_f, TIME_LIMIT].min
        @scopes = scopes
        @request_id = request_id
        @timestamp = timestamp
      end

      def call
        address = self.class.address(@row)
        raise Error::StoreDataUnavailable.new('no address of the store app', code: 'no_address') unless address && Provisioning.enabled?
        raise Error::StoreDataUnavailable.new('no time left to ask the store app', code: 'no_time') if @time_limit < 1

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = nil
        begin
          response = post(address)
          status = response.code.to_i
          grant = read(response, status)
          finish('key_granted', status, started)
          grant
        rescue Error::AppKeyRefused => e
          finish("key_refused:#{e.reason == 'app_removed' ? 'store_not_installed' : e.reason}", status, started)
          raise
        rescue Error::StoreDataUnavailable => e
          finish(outcome_for(e), status, started)
          alarm if e.code == 'unauthorized'
          raise
        end
      end

      private

      def body
        @body ||= { contract: Provisioning::CONTRACT, account_id: @account_id, scopes: @scopes }.to_json
      end

      def post(address)
        uri = URI.parse("#{address}/stores/#{@row.shop_domain}/store-key")
        signature = Provisioning::Signature.sign(secret, timestamp: @timestamp, request_id: @request_id, method: 'POST', path: uri.path, body: body)
        headers = {
          'Content-Type' => 'application/json', 'Accept' => 'application/json',
          'X-Inclamo-Timestamp' => @timestamp.to_s, 'X-Inclamo-Request-Id' => @request_id, 'X-Inclamo-Signature' => signature
        }
        Timeout.timeout(@time_limit) { transport(uri, headers) }
      rescue Error
        raise
      rescue StandardError, Timeout::Error => e
        # The class only: a message may name the address.
        raise Error::StoreDataUnavailable.new("the store app did not answer: #{e.class}", code: 'no_answer')
      end

      # Never follows a redirect. Where Chatwoot may reach private networks
      # (a test stack), the address is called directly, as SafeFetch does there.
      def transport(uri, headers)
        return private_network(uri, headers) if SafeFetch.allow_private_network?

        options = SafeFetch::RequestOptions.new(url: uri.to_s, method: :post, body: body, headers: headers, resolver: self.class.resolver,
                                                open_timeout: @time_limit, read_timeout: @time_limit, validate_content_type: false)
        SsrfFilter.post(options.url, **options.request_options, max_redirects: 0, allow_unfollowed_redirects: true)
      end

      def private_network(uri, headers)
        request = Net::HTTP::Post.new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = body
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @time_limit, read_timeout: @time_limit) do |http|
          http.request(request)
        end
      end

      # The current secret signs; the previous one, kept while the app is
      # switched over, only checks the app's calls.
      def secret
        Provisioning.secrets.first
      end

      def read(response, status)
        answer = parse(response)
        return grant(answer) if status == 200

        code = answer['error'].to_s if answer['error'].is_a?(String) && CODE.match?(answer['error'])
        reason = BREAKING[[status, code]]
        raise Error::AppKeyRefused, reason if reason

        raise Error::StoreDataUnavailable.new("the store app answered #{status}", code: refusal_code(status, code), retry_after: retry_after(response))
      end

      # A refusal for now names the app's code; anything else is no answer.
      def refusal_code(status, code)
        case status
        when 401 then 'unauthorized'
        when 422 then code || 'unprocessable'
        when 429 then code || 'rate_limited'
        when 503 then code || 'store_unavailable'
        when 300..399 then 'redirect'
        else 'no_answer'
        end
      end

      def grant(answer)
        raise unreadable unless answer['contract'].nil? || answer['contract'] == Provisioning::CONTRACT

        token = answer['access_token']
        scopes = answer['scopes']
        raise unreadable unless token.is_a?(String) && token.present? && scopes.is_a?(Array) && scopes.all?(String)
        raise Error::OtherStoreKey unless answer['shop_domain'].to_s.strip.downcase == @row.shop_domain

        expires_at = Time.iso8601(answer['expires_at'].to_s)
        raise Error::StoreDataUnavailable.new('the key the store app gave ends too soon', code: 'short_life') if expires_at < MIN_LIFE.from_now

        # Never more than was asked for, whatever the answer lists.
        Grant.new(shop_domain: @row.shop_domain, access_token: token, expires_at: expires_at, scopes: (scopes & @scopes).sort)
      rescue ArgumentError
        raise unreadable
      end

      def unreadable
        Error::StoreDataUnavailable.new('the store app sent a key that does not read', code: 'unreadable')
      end

      def parse(response)
        text = response.body.to_s
        data = text.bytesize <= MAX_ANSWER ? JSON.parse(text) : nil
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end

      def retry_after(response)
        value = Integer(response['Retry-After'].to_s.strip, 10, exception: false)
        value if value&.positive?
      end

      def outcome_for(error)
        case error.code
        when 'other_store', 'short_life', 'unreadable' then "key_invalid:#{error.code}"
        when 'no_answer', 'redirect' then 'key_no_answer'
        else "key_refused:#{error.code}"
        end
      end

      def finish(outcome, status, started)
        Inclamo::ProvisioningEvent.record(outcome: outcome, shop_domain: @row.shop_domain, request_id: @request_id, account_id: @account_id)
        milliseconds = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Rails.logger.info("[inclamo store key] account #{@account_id}: #{outcome} (status #{status || 'none'}, #{milliseconds} ms)")
      end

      def alarm
        ChatwootExceptionTracker.new(
          SecretRefused.new("the store app refused the helpdesk's signature for account #{@account_id}: the shared secret differs on the two sides")
        ).capture_exception
      end
    end
  end
end
