# frozen_string_literal: true

module Inclamo::Support::Feed
  module_function

  def public?(message)
    !message.private? && !message.deleted && (message.incoming? || message.outgoing?)
  end

  def serialize(message)
    return { 'kind' => 'removed', 'message_id' => message.id.to_s } unless public?(message)

    actor = message.content_attributes&.fetch('inclamo_support_actor', nil)
    actor ||= { 'name' => message.sender&.try(:name).to_s.first(120), 'administrator' => false }
    { 'kind' => 'message', 'message_id' => message.id.to_s,
      'submission_uuid' => message.content_attributes&.fetch('inclamo_support_submission', nil),
      'body' => message.content, 'actor' => actor.slice('name', 'administrator'),
      'direction' => message.outgoing? ? 'support' : 'requester', 'sent_at' => message.created_at.iso8601,
      'files' => message.attachments.map do |attachment|
        next unless attachment.file.attached?

        { 'id' => attachment.id.to_s, 'filename' => attachment.file.filename.to_s,
          'type' => attachment.file.content_type, 'size' => attachment.file.byte_size }
      end.compact }
  end

  # The client pages through a source's events by id (`cursor`), so the
  # events of one source must become visible in id order: an event committed
  # after a higher id was read would be skipped for good. New events are
  # therefore inserted together at the end, under a per-source lock held
  # until commit (`publish!`); reconciliations that insert nothing take no lock.
  def reconcile!(mapping)
    mapping.with_lock do
      conversation = mapping.conversation.reload
      fresh = []
      if mapping.last_status != conversation.status
        fresh << ["status:#{SecureRandom.uuid}", { 'kind' => 'status', 'status' => conversation.status }]
        mapping.update!(last_status: conversation.status)
      end
      current_ids = []
      conversation.messages.includes(:sender, attachments: { file_attachment: :blob }).find_each do |message|
        current_ids << message.id.to_s
        # Private notes never enter the feed. A public message later made private
        # emits only a tombstone to invalidate an older client cache.
        prior = Inclamo::Support::Event.where(central_request_id: mapping.id).where("identity LIKE ?", "message:#{message.id}:%").exists?
        next unless public?(message) || prior

        identity = "message:#{message.id}:#{message.updated_at.utc.iso8601(6)}:#{message.private?}"
        fresh << [identity, serialize(message)]
        Inclamo::Support::Recipients.notify!(mapping, message) if message.outgoing? && public?(message)
      end
      known_ids = Inclamo::Support::Event.where(central_request_id: mapping.id)
                      .where("payload->>'kind' = 'message'").distinct.pluck(Arel.sql("payload->>'message_id'"))
      (known_ids - current_ids).each do |id|
        fresh << ["removed:#{id}", { 'kind' => 'removed', 'message_id' => id }]
      end
      publish!(mapping, fresh)
    end
  end

  # Inserts the events not recorded yet, in order. Must run inside the
  # caller's transaction: the source's lock is released only at its commit.
  def publish!(mapping, entries)
    known = Inclamo::Support::Event.where(central_request_id: mapping.id, identity: entries.map(&:first)).pluck(:identity)
    entries = entries.reject { |entry| known.include?(entry.first) }
    return if entries.empty?

    lock_feed!(mapping.source_id)
    entries.each { |identity, payload| event!(mapping, identity, payload) }
  end

  def lock_feed!(source_id)
    key = Digest::SHA256.hexdigest("inclamo-support-feed:#{source_id}").first(15).to_i(16)
    ActiveRecord::Base.connection.select_value("SELECT pg_advisory_xact_lock(#{key})")
  end

  def event!(mapping, identity, payload)
    Inclamo::Support::Event.create_or_find_by!(central_request_id: mapping.id, identity: identity) do |event|
      event.source_id = mapping.source_id
      event.payload = payload.merge('request_reference' => mapping.local_reference, 'central_reference' => mapping.reference)
    end
  end

  def safe_payload(event)
    payload = event.payload
    return payload unless payload['kind'] == 'message'

    message = ::Message.find_by(id: payload['message_id'], conversation_id: event.central_request.conversation_id)
    # Recheck visibility before returning cached events, including attachments.
    if !message || !public?(message)
      payload.slice('request_reference', 'central_reference').merge('kind' => 'removed', 'message_id' => payload['message_id'])
    else
      payload
    end
  end

  def import!(event)
    request = Inclamo::Support::Request.find_by(reference: event['request_reference'])
    return unless request

    request.with_lock do
      raise Inclamo::Support::Conflict if request.central_reference.present? && request.central_reference != event['central_reference']

      request.central_reference = event['central_reference']
      case event['kind']
      when 'status'
        request.status = event['status'] if %w[open resolved pending snoozed].include?(event['status'])
      when 'removed'
        request.messages.where(central_message_id: event['message_id']).destroy_all
      when 'message'
        message = request.messages.find_or_initialize_by(central_message_id: event.fetch('message_id'))
        is_new = message.new_record?
        message.update!(submission_uuid: event['submission_uuid'], body: event['body'], actor: event['actor'],
                        direction: event['direction'], sent_at: event['sent_at'], files: event['files'])
        request.last_reply_id = message.id if is_new && message.direction == 'support'
      end
      request.save!
    end
  end
end
