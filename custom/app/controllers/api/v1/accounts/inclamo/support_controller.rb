# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::SupportController < Api::V1::Accounts::BaseController
  before_action :find_request, only: [:show, :reply, :read, :retry_delivery, :attachment, :upload_download, :recipient, :verify_recipient]
  rescue_from ::Inclamo::Support::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from ::Inclamo::Support::Conflict do
    render json: { error: 'submission_conflict' }, status: :conflict
  end
  rescue_from ::Inclamo::Support::Unauthorized do
    head :not_found
  end
  rescue_from ::Inclamo::Support::RateLimited do
    render json: { error: 'rate_limited' }, status: :too_many_requests
  end
  rescue_from ::Inclamo::Support::Unavailable do
    render json: { error: 'support_unavailable' }, status: :service_unavailable
  end
  rescue_from ActiveRecord::RecordInvalid do
    render json: { error: 'invalid_request' }, status: :unprocessable_entity
  end

  def metadata
    render json: { author: ::Inclamo::Support.actor(Current.account_user).slice('name', 'email'),
                   account: { id: Current.account.id, name: Current.account.name },
                   version: File.read(Rails.root.join('custom/INCLAMO_VERSION')).strip,
                   max_files: ::Inclamo::Support::MAX_FILES, max_bytes: ::Inclamo::Support::MAX_BYTES }
  end

  def index
    schedule_sync
    requests = scope.order(updated_at: :desc).limit(100)
    render json: { requests: requests.map { |item| service.serialize(item) } }
  end

  def show
    schedule_sync
    render json: service.serialize(@request, detail: true)
  end

  def create
    context = params[:context].is_a?(ActionController::Parameters) ? params[:context].permit(:browser, :location, :conversation_reference).to_h : {}
    request = service.create!(submission_params.merge('category' => params[:category], 'context' => context))
    schedule_delivery(request.submissions.last)
    render json: service.serialize(request, detail: true), status: :created
  end

  def reply
    submission = service.append!(@request, submission_params)
    schedule_delivery(submission)
    render json: service.serialize(@request, detail: true), status: :created
  end

  def read
    cursor = params[:cursor]
    raise ::Inclamo::Support::Invalid, 'invalid_cursor' unless cursor.is_a?(Integer) && cursor >= 0 && cursor <= @request.last_reply_id

    record = @request.reads.create_or_find_by!(account_user_id: Current.account_user.id)
    record.with_lock { record.update!(last_reply_id: [record.last_reply_id, cursor].max) }
    head :no_content
  end

  def retry_delivery
    submission = @request.submissions.find_by!(uuid: params[:uuid])
    submission.update!(state: 'queued', next_attempt_at: nil)
    schedule_delivery(submission)
    render json: service.serialize(@request, detail: true)
  end

  def upload
    file = params[:file]
    raise ::Inclamo::Support::Invalid, 'invalid_file' unless file.respond_to?(:read)

    ::Inclamo::Support::Authentication.rate!("upload:#{Current.account_user.id}", limit: 20)
    bytes = file.read(::Inclamo::Support::MAX_BYTES + 1)
    upload = ::Inclamo::Support::Files.stage!(bytes: bytes, filename: file.original_filename, owner: { account_user_id: Current.account_user.id })
    render json: ::Inclamo::Support::Files.describe(upload), status: :created
  end

  def upload_download
    upload = ::Inclamo::Support::Upload.where(submission_id: @request.submissions.select(:id)).find_by!(reference: params[:file_id])
    send_safe_file(upload.file.download, upload.file.content_type, upload.file.filename.to_s)
  end

  def attachment
    result = ::Inclamo::Support::Transport.new.download(@request, params[:file_id])
    send_safe_file(result.fetch(:bytes), result.fetch(:type), result.fetch(:filename))
  end

  def recipient
    raise ::Inclamo::Support::Unauthorized unless @request.author_id == Current.user.id

    if [true, false].include?(params[:enabled])
      preference = ::Inclamo::Support::NotificationPreference.find_or_initialize_by(account_user_id: Current.account_user.id)
      preference.update!(enabled: params[:enabled])
    end
    render json: ::Inclamo::Support::Transport.new.recipient(@request, Current.account_user, verify: false)
  end

  def verify_recipient
    raise ::Inclamo::Support::Unauthorized unless @request.author_id == Current.user.id

    render json: ::Inclamo::Support::Transport.new.recipient(@request, Current.account_user, verify: true, code: params[:code].to_s)
  end

  private

  def scope
    ::Inclamo::Support::Request.visible_to(Current.account_user)
  end

  def find_request
    @request = scope.find_by!(reference: params[:id])
  end

  def service
    @service ||= ::Inclamo::Support::LocalRequests.new(Current.account_user)
  end

  def submission_params
    params.permit(:uuid, :body, files: []).to_h
  end

  def schedule_delivery(submission)
    ::Inclamo::Support::DeliverJob.perform_later(submission.id)
  rescue StandardError => error
    # The durable outbox is recovered by the periodic dispatcher after a queue outage.
    Rails.logger.warn("Inclamo support enqueue failed: #{error.class}")
  end

  def schedule_sync
    ::Inclamo::Support::SyncJob.perform_later(@request&.id)
  rescue StandardError => error
    Rails.logger.warn("Inclamo support sync enqueue failed: #{error.class}")
  end

  def send_safe_file(bytes, type, filename)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox"
    send_data bytes, type: type, filename: filename, disposition: 'attachment'
  end
end
