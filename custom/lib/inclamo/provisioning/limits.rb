# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The request limits, as Rack::Attack rules, one count each (see
    # Provisioning::ADDRESSES for which request joins which):
    #   put        the `PUT`s of the installation as a whole;
    #   put/store  the `PUT`s of one store, every address's `PUT` together;
    #   get        the status calls of the installation, every address's together.
    # The removal notice joins none of them.
    #
    # Only requests that pass the gate and will be acted on are counted: a
    # request answered from its stored answer, or one still being answered,
    # does not count, and traffic that is not the store app's cannot spend its
    # allowance; Chatwoot's per-address throttle stays in front for that
    # traffic. A request refused for its body counts. Like every Rack::Attack
    # rule they follow the installation's ENABLE_RACK_ATTACK and its list of
    # trusted addresses.
    module Limits
      PREFIX = 'inclamo/provisioning/'
      PERIOD = 3600
      COUNTED = 'inclamo.provisioning.counted'

      module_function

      # Called once per process (custom/config/overlay.rb).
      def install
        return if Rack::Attack.throttles.key?("#{PREFIX}put")

        Rack::Attack.throttle("#{PREFIX}put", limit: ->(_) { Provisioning.limit(:put) }, period: PERIOD) do |request|
          'installation' if Limits.counted(request)&.count == :put
        end
        Rack::Attack.throttle("#{PREFIX}put/store", limit: ->(_) { Provisioning.limit(:store) }, period: PERIOD) do |request|
          verdict = Limits.counted(request)
          verdict.shop_domain if verdict&.count == :put
        end
        Rack::Attack.throttle("#{PREFIX}get", limit: ->(_) { Provisioning.limit(:get) }, period: PERIOD) do |request|
          'installation' if Limits.counted(request)&.count == :get
        end

        default = Rack::Attack.throttled_responder
        Rack::Attack.throttled_responder = lambda do |request|
          request.env['rack.attack.matched'].to_s.start_with?(PREFIX) ? Limits.refuse(request) : default.call(request)
        end
      end

      # The gate's verdict for a provisioning request that passed and whose
      # request id is new, else nil. Worked out once per request.
      def counted(request)
        return unless request.path.start_with?(PATH_PREFIX) && Provisioning.enabled?
        return request.env[COUNTED] if request.env.key?(COUNTED)

        verdict = Gate.check(request.env)
        request.env[COUNTED] = (verdict if verdict.passed? && verdict.count && !RequestStore.seen?(verdict.request_id))
      end

      def refuse(request)
        verdict = Gate.check(request.env)
        ProvisioningEvent.record(outcome: 'limited', shop_domain: verdict.shop_domain, request_id: verdict.request_id)
        match = request.env['rack.attack.match_data']
        retry_after = match[:period] - (match[:epoch_time] % match[:period])
        [429, { 'content-type' => 'application/json; charset=utf-8', 'retry-after' => retry_after.to_s },
         [{ error: 'rate_limited' }.to_json]]
      end
    end
  end
end
