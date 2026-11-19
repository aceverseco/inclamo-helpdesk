# frozen_string_literal: true

module Inclamo
  module Provisioning
    # Request ids seen in the last ten minutes, each with a digest of what was
    # asked and the answer that was given. The same id with the same request is
    # answered from here without acting again; the same id with another request
    # is refused. This cache is the only place a stored answer (and so a
    # password link) is kept: nothing here is written to a log or to the record
    # of attempts, and it goes after ten minutes.
    module RequestStore
      KEEP = 600
      # How long an id stays taken while its first request is still being
      # answered; a process that died mid-request frees the id after this.
      PENDING = 30
      KEY = 'INCLAMO_PROVISIONING_REQUEST::%<id>s'

      Answer = Struct.new(:status, :body, :outcome, keyword_init: true)

      module_function

      # The digest covers the method and the path with the body: two calls
      # without a body (status, removal) for different stores differ by it.
      def digest(method:, path:, body:)
        Digest::SHA256.hexdigest("#{method.to_s.upcase}.#{path}.#{body}")
      end

      # Whether the id is taken: answered, or being answered.
      def seen?(id)
        Redis::Alfred.exists?(key(id))
      end

      # :reserved when the id is new and now taken by this request, :conflict
      # when it belongs to another request, :pending when the same request is
      # still being answered, or the stored Answer.
      def reserve(id, digest)
        return :reserved if Redis::Alfred.set(key(id), { digest: digest }.to_json, nx: true, ex: PENDING)

        entry = read(id)
        return reserve(id, digest) if entry.nil?
        return :conflict unless entry['digest'] == digest

        entry['status'] ? answer(entry) : :pending
      end

      def answer_for(id, digest)
        entry = read(id)
        answer(entry) if entry && entry['digest'] == digest && entry['status']
      end

      def keep(id, digest, status:, body:, outcome:)
        Redis::Alfred.set(key(id), { digest: digest, status: status, body: body, outcome: outcome }.to_json, ex: KEEP)
      end

      def release(id)
        Redis::Alfred.delete(key(id))
      end

      def key(id)
        format(KEY, id: id.to_s.downcase)
      end

      def read(id)
        raw = Redis::Alfred.get(key(id))
        raw && JSON.parse(raw)
      end

      def answer(entry)
        Answer.new(status: entry['status'], body: entry['body'], outcome: entry['outcome'])
      end
    end
  end
end
