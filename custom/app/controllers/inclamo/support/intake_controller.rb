# frozen_string_literal: true

# Deliberately separate from staff/session authentication. Every authenticated
# operation resolves a source from its signature, never from payload routing IDs.
class Inclamo::Support::IntakeController < ActionController::API
  FEED_BYTES = 4 * 1024 * 1024

  before_action :enabled
  before_action :read_body
  before_action :authenticate_source, except: [:register]
  rescue_from Inclamo::Support::Unauthorized, with: -> { head :unauthorized }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from Inclamo::Support::Conflict, with: -> { render json: { error: 'identity_conflict' }, status: :conflict }
  rescue_from Inclamo::Support::RateLimited, with: -> { head :too_many_requests }
  rescue_from Inclamo::Support::Invalid, JSON::ParserError, ArgumentError, KeyError do |error|
    render json: { error: error.is_a?(Inclamo::Support::Invalid) ? error.message : 'invalid_payload' }, status: :unprocessable_entity
  end
  rescue_from Inclamo::Support::Unavailable, with: -> { head :service_unavailable }

  def register
    Inclamo::Support::Authentication.rate!("enrollment:#{request.remote_ip}", limit: 10, seconds: 3600)
    value = payload
    public_key = value.fetch('public_key')
    raise Inclamo::Support::Invalid, 'invalid_key' unless public_key.is_a?(String) && public_key.bytesize <= 512

    Inclamo::Support::Authentication.verify!(public_key, request.headers['X-Inclamo-Signature'], request.method,
                                            request.fullpath, request.headers['X-Inclamo-Timestamp'], @body)
    base_url = Inclamo::Support.valid_url!(value.fetch('base_url'))
    fingerprint = Inclamo::Support::Authentication.fingerprint(public_key)
    source = Inclamo::Support::Source.create_or_find_by!(fingerprint: fingerprint) do |record|
      record.reference = SecureRandom.uuid
      record.public_key = public_key
      record.base_url = base_url
      record.hosted = false
    end
    raise Inclamo::Support::Unauthorized if source.revoked_at
    raise Inclamo::Support::Conflict unless source.base_url == base_url

    render json: { source_id: source.reference }
  end

  def submit
    render json: Inclamo::Support::Intake.new(@source).submit!(payload)
  end

  def upload
    value = payload
    bytes = Base64.strict_decode64(value.fetch('bytes'))
    upload = nil
    @source.with_lock do
      upload = Inclamo::Support::Files.stage!(bytes: bytes, filename: value.fetch('filename'),
                                             reference: value.fetch('reference'), owner: { source_id: @source.id })
    end
    render json: Inclamo::Support::Files.describe(upload)
  end

  def sync
    cursor = Integer(params.fetch(:cursor, '0'), 10)
    raise Inclamo::Support::Invalid, 'invalid_cursor' if cursor.negative?

    # A missed listener is repaired independently by the scheduled reconciler.
    candidates = Inclamo::Support::Event.where(source_id: @source.id).where('id > ?', cursor).order(:id).limit(100).to_a
    events = []
    bytes = 0
    candidates.each do |event|
      value = { id: event.id, **Inclamo::Support::Feed.safe_payload(event).symbolize_keys }
      size = value.to_json.bytesize
      break if events.any? && bytes + size > FEED_BYTES

      events << value
      bytes += size
    end
    render json: { events: events, cursor: events.last&.fetch(:id) || cursor,
                   more: candidates.size == 100 || events.size < candidates.size }
  end

  def reconcile
    mapping = @source.requests.find_by!(reference: params[:id])
    Inclamo::Support::Feed.reconcile!(mapping)
    render json: { status: mapping.conversation.reload.status }
  end

  def attachment
    mapping = @source.requests.find_by!(reference: params[:id])
    file = Attachment.joins(:message).where(messages: { conversation_id: mapping.conversation_id, private: false, message_type: [0, 1] }).find(params[:file_id])
    raise ActiveRecord::RecordNotFound unless Inclamo::Support::Feed.public?(file.message) && file.file.attached?
    raise Inclamo::Support::Invalid, 'file_size' if file.file.byte_size > Inclamo::Support::MAX_BYTES

    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Cache-Control'] = 'private, no-store'
    send_data file.file.download, filename: file.file.filename.to_s, type: file.file.content_type, disposition: 'attachment'
  end

  def recipients
    render json: Inclamo::Support::Recipients.sync!(@source, payload)
  end

  def verify_recipient
    render json: Inclamo::Support::Recipients.verify!(@source, payload)
  end

  private

  def enabled
    head :not_found unless Inclamo::Support.central?
  end

  def read_body
    limit = action_name == 'upload' ? (Inclamo::Support::MAX_BYTES * 4 / 3 + 4096) : (Inclamo::Support::MAX_BODY * 4 + 65_536)
    @body = request.body&.read(limit + 1).to_s
    raise Inclamo::Support::Invalid, 'body_size' if @body.bytesize > limit

    request.set_header('RAW_POST_DATA', @body)
  end

  def authenticate_source
    @source = Inclamo::Support::Source.find_by!(reference: request.headers['X-Inclamo-Source'], revoked_at: nil)
    Inclamo::Support::Authentication.verify!(@source.public_key, request.headers['X-Inclamo-Signature'], request.method,
                                            request.fullpath, request.headers['X-Inclamo-Timestamp'], @body)
    Inclamo::Support::Authentication.rate!("source:#{@source.id}", limit: 120)
  end

  def payload
    @payload ||= JSON.parse(@body).tap { |value| raise Inclamo::Support::Invalid, 'invalid_payload' unless value.is_a?(Hash) }
  end
end
