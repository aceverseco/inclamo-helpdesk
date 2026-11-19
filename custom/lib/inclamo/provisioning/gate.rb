# frozen_string_literal: true

module Inclamo
  module Provisioning
    # Decides whether a request to a provisioning address comes from the store
    # app: a signature made with the shared secret, a time within five minutes
    # of ours, and a request id not already used for something else. Nothing
    # says which of the checks failed.
    #
    # The verdict is kept in the Rack environment: the request limits (which
    # count only requests that pass) and the controller read the same one.
    module Gate
      ENV_KEY = 'inclamo.provisioning.verdict'
      PATH = %r{\A/inclamo/provisioning/stores/(?<domain>[^/]+)(?<removal>/removal)?\z}
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      MAX_BODY = 64 * 1024

      Verdict = Struct.new(:passed, :shop_domain, :request_id, :digest, keyword_init: true) do
        def passed?
          passed == true
        end
      end

      module_function

      def check(env)
        env[ENV_KEY] ||= verdict(ActionDispatch::Request.new(env))
      end

      def verdict(request)
        match = PATH.match(request.path)
        shop_domain = match && match[:domain].downcase
        request_id = request.get_header('HTTP_X_INCLAMO_REQUEST_ID').to_s.downcase
        refused = Verdict.new(passed: false, shop_domain: shop_domain, request_id: request_id)
        return refused unless match && request.content_length.to_i <= MAX_BODY

        parts = { method: request.request_method, path: request.path, body: request.raw_post.to_s }
        return refused unless signed?(request, parts) && UUID.match?(request_id)

        digest = RequestStore.digest(**parts)
        return refused if RequestStore.conflict?(request_id, digest)

        Verdict.new(passed: true, shop_domain: shop_domain, request_id: request_id, digest: digest)
      end

      def signed?(request, parts)
        timestamp = request.get_header('HTTP_X_INCLAMO_TIMESTAMP').to_s
        secrets = Provisioning.secrets
        # Both checks always run, so a refusal takes the same time for either.
        matched = Signature.match?(secrets, request.get_header('HTTP_X_INCLAMO_SIGNATURE'), timestamp: timestamp, **parts)
        fresh = Signature.fresh?(timestamp)
        secrets.any? && matched && fresh
      end
    end
  end
end
