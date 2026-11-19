# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The limits of a staff member's entry (docs/app-admin-entry.md §4), as
    # Rack::Attack rules next to the other provisioning limits (Limits):
    #   inclamo/provisioning/entry/store   the app's entry requests for one store;
    #   inclamo/provisioning/entry/person  those for one person in one store,
    #       counted under a keyed digest of the email, so no counter's key
    #       holds an email;
    #   inclamo/entry/ip   the openings of one-time addresses from one network
    #       address, the sign-in limit of this way in. Chatwoot's limits on its
    #       sign-in form stay as they are.
    # The app's requests are counted as Limits counts: only signed requests
    # with a new request id, and a request refused for its body too. A request
    # over its limit is answered by Limits (429 with Retry-After); an opening
    # over its limit signs nobody in and shows the login page, and its address
    # stays usable for the rest of its minute.
    module EntryLimits
      STORE = 'inclamo/provisioning/entry/store'
      PERSON = 'inclamo/provisioning/entry/person'
      OPENING = 'inclamo/entry/ip'
      HOUR = 3600
      OPENING_PERIOD = 300
      PERSON_KEY = 'inclamo.entry.person'

      # Operator settings, with these defaults.
      LIMITS = {
        store: ['INCLAMO_APP_PROVISIONING_ENTRY_STORE_LIMIT', 300],
        person: ['INCLAMO_APP_PROVISIONING_ENTRY_PERSON_LIMIT', 20],
        opening: ['INCLAMO_APP_PROVISIONING_ENTRY_OPEN_LIMIT', 30]
      }.freeze

      module_function

      # Called once per process, after Limits.install (custom/config/overlay.rb).
      def install
        return if Rack::Attack.throttles.key?(STORE)

        Rack::Attack.throttle(STORE, limit: ->(_) { limit(:store) }, period: HOUR) do |request|
          entry(request)&.shop_domain
        end
        Rack::Attack.throttle(PERSON, limit: ->(_) { limit(:person) }, period: HOUR) do |request|
          verdict = entry(request)
          person = verdict && person(request)
          "#{verdict.shop_domain}:#{person}" if person
        end
        Rack::Attack.throttle(OPENING, limit: ->(_) { limit(:opening) }, period: OPENING_PERIOD) do |request|
          request.ip if request.get? && request.path == InclamoEntryPath::PATH && Provisioning.enabled?
        end

        others = Rack::Attack.throttled_responder
        Rack::Attack.throttled_responder = lambda do |request|
          request.env['rack.attack.matched'] == OPENING ? [302, { 'location' => '/app/login' }, []] : others.call(request)
        end
      end

      def limit(name)
        variable, default = LIMITS.fetch(name)
        value = Integer(ENV.fetch(variable, '').strip, 10, exception: false)
        value&.positive? ? value : default
      end

      # The gate's verdict for a counted entry request, else nil.
      def entry(request)
        verdict = Limits.counted(request)
        verdict if verdict&.count == :entry
      end

      # A keyed digest of the request's email, nil when it names none.
      def person(request)
        return request.env[PERSON_KEY] if request.env.key?(PERSON_KEY)

        staff = JSON.parse(ActionDispatch::Request.new(request.env).raw_post.to_s)['staff']
        email = EntryPayload.email(staff['email']) if staff.is_a?(Hash)
        request.env[PERSON_KEY] = (OpenSSL::HMAC.hexdigest('SHA256', person_key, email) if email)
      rescue JSON::ParserError, TypeError, NoMethodError
        request.env[PERSON_KEY] = nil
      end

      def person_key
        @person_key ||= Rails.application.key_generator.generate_key('inclamo/provisioning/entry/person', 32)
      end
    end
  end
end
