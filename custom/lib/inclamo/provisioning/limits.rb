# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The request limits, as Rack::Attack rules: "the store has an account"
    # for the installation as a whole and for one store, and the status call.
    # Only requests that pass the gate are counted, so traffic that is not the
    # store app's cannot spend its allowance; Chatwoot's per-address throttle
    # stays in front for that traffic. Like every Rack::Attack rule they follow
    # the installation's ENABLE_RACK_ATTACK and its list of trusted addresses.
    module Limits
      PREFIX = 'inclamo/provisioning/'
      PERIOD = 3600

      module_function

      # Called once per process (custom/config/overlay.rb).
      def install
        return if Rack::Attack.throttles.key?("#{PREFIX}put")

        Rack::Attack.throttle("#{PREFIX}put", limit: ->(_) { Provisioning.limit(:put) }, period: PERIOD) do |request|
          'installation' if request.put? && Limits.counted(request)
        end
        Rack::Attack.throttle("#{PREFIX}put/store", limit: ->(_) { Provisioning.limit(:store) }, period: PERIOD) do |request|
          Limits.counted(request)&.shop_domain if request.put?
        end
        Rack::Attack.throttle("#{PREFIX}get", limit: ->(_) { Provisioning.limit(:get) }, period: PERIOD) do |request|
          'installation' if request.get? && Limits.counted(request)
        end

        default = Rack::Attack.throttled_responder
        Rack::Attack.throttled_responder = lambda do |request|
          request.env['rack.attack.matched'].to_s.start_with?(PREFIX) ? Limits.refuse(request) : default.call(request)
        end
      end

      # The gate's verdict for a provisioning request that passed, else nil.
      def counted(request)
        return unless request.path.start_with?('/inclamo/provisioning/') && Provisioning.enabled?

        verdict = Gate.check(request.env)
        verdict if verdict.passed?
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
