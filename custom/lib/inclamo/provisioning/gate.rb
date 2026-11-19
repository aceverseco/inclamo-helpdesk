# frozen_string_literal: true

module Inclamo
  module Provisioning
    # Decides whether a request to a provisioning address comes from the store
    # app: one of the store app's addresses (Provisioning::ADDRESSES), a
    # signature made with the shared secret, a time within five minutes of
    # ours and a request id that reads as a UUID. Nothing says which of the
    # checks failed. Whether the request id was already used for another
    # request is the controller's question, asked after this one passed.
    #
    # The verdict is kept in the Rack environment: the request limits (which
    # count only requests that pass) and the controller read the same one.
    module Gate
      ENV_KEY = 'inclamo.provisioning.verdict'
      PATH = %r{\A/inclamo/provisioning/stores/(?<domain>[^/]+)(?<address>(?:/[^/]+){1,2})?\z}
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      MAX_BODY = 64 * 1024

      # `count` is the hourly count the request joins (see
      # Provisioning::ADDRESSES), nil for one that is not limited.
      Verdict = Struct.new(:passed, :shop_domain, :request_id, :digest, :count, keyword_init: true) do
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
        sent_id = request.get_header('HTTP_X_INCLAMO_REQUEST_ID').to_s
        refused = Verdict.new(passed: false, shop_domain: shop_domain, request_id: sent_id.downcase)
        methods = match && Provisioning::ADDRESSES[match[:address].to_s]
        return refused unless methods && request.content_length.to_i <= MAX_BODY

        parts = { method: request.request_method, path: request.path, body: request.raw_post.to_s }
        return refused unless signed?(request, sent_id, parts) && UUID.match?(sent_id)

        Verdict.new(passed: true, shop_domain: shop_domain, request_id: sent_id.downcase, digest: RequestStore.digest(**parts),
                    count: methods[request.request_method])
      end

      def signed?(request, request_id, parts)
        timestamp = request.get_header('HTTP_X_INCLAMO_TIMESTAMP').to_s
        secrets = Provisioning.secrets
        # Both checks always run, so a refusal takes the same time for either.
        matched = Signature.match?(secrets, request.get_header('HTTP_X_INCLAMO_SIGNATURE'), timestamp: timestamp,
                                                                                              request_id: request_id, **parts)
        fresh = Signature.fresh?(timestamp)
        secrets.any? && matched && fresh
      end
    end
  end
end
