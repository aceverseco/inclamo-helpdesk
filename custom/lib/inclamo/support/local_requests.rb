# frozen_string_literal: true

class Inclamo::Support::LocalRequests
  def initialize(member)
    @member = member
  end

  def create!(params)
    uuid = params['uuid'].to_s
    raise Inclamo::Support::Invalid, 'invalid_reference' unless uuid.match?(Inclamo::Support::UUID)

    @member.with_lock do
      existing = Inclamo::Support::Request.find_by(reference: uuid)
      if existing
        raise Inclamo::Support::Conflict unless existing.author_id == @member.user_id && existing.account_id == @member.account_id
        verify_retry!(existing.submissions.order(:id).first!, params)
        return existing
      end
      request = Inclamo::Support::Request.create!(
        reference: uuid, account_id: @member.account_id, author_id: @member.user_id,
        author_key: "user:#{@member.user_id}", author_snapshot: Inclamo::Support.actor(@member),
        category: params['category'], context: context(params['context'] || {})
      )
      append!(request, params)
      request
    end
  end

  def append!(request, params)
    raise Inclamo::Support::Unauthorized unless request.accessible_by?(@member.reload)

    submission = nil
    request.with_lock do
      existing = request.submissions.find_by(uuid: params['uuid'])
      if existing
        raise Inclamo::Support::Conflict unless existing.actor_id == @member.user_id

        verify_retry!(existing, params)
        return existing
      end
      files = Array(params['files'])
      raise Inclamo::Support::Invalid, 'file_count' if files.size > Inclamo::Support::MAX_FILES || files.uniq.size != files.size

      uploads = Inclamo::Support::Upload.where(account_user_id: @member.id, source_id: nil, submission_id: nil, reference: files).lock.to_a
      raise Inclamo::Support::Invalid, 'invalid_files' unless uploads.size == files.size && uploads.all? { |file| file.created_at > 24.hours.ago }

      submission = request.submissions.create!(uuid: params['uuid'], body: params['body'].to_s.strip,
                                              actor_id: @member.user_id, actor_snapshot: Inclamo::Support.actor(@member))
      uploads.each { |file| file.update!(submission_id: submission.id) }
    end
    submission
  rescue ActiveRecord::RecordNotUnique
    raise Inclamo::Support::Conflict
  end

  def serialize(request, detail: false)
    read = request.reads.find_by(account_user_id: @member.id)
    submissions = request.submissions.order(:id)
    result = {
      reference: request.reference, author: request.author_snapshot.slice('name', 'administrator'), category: request.category,
      status: request.status, created_at: request.created_at, context: request.context,
      unread: request.last_reply_id > read&.last_reply_id.to_i,
      preview: submissions.first&.body.to_s.first(160),
      delivery: %w[failed attachments_pending queued delivered].find { |state| submissions.any? { |submission| submission.state == state } },
      can_verify_email: request.author_id == @member.user_id,
      notifications_enabled: Inclamo::Support::NotificationPreference.enabled_for?(@member)
    }
    return result unless detail

    result[:last_reply_id] = request.last_reply_id
    result[:messages] = request.messages.order(:sent_at, :id).map do |message|
      { id: message.central_message_id, submission_uuid: message.submission_uuid, body: message.body, actor: message.actor,
        direction: message.direction, sent_at: message.sent_at,
        files: message.files.map { |file| file.merge('url' => download_url(request, file['id'])) } }
    end
    result[:submissions] = submissions.map do |submission|
      { uuid: submission.uuid, body: submission.body, actor: submission.actor_snapshot.slice('name', 'administrator'),
        state: submission.state, error: submission.error_code, created_at: submission.created_at,
        files: submission.uploads.map { |upload| Inclamo::Support::Files.describe(upload).merge(url: local_download_url(request, upload.reference)) } }
    end
    result
  end

  private

  def verify_retry!(existing, params)
    raise Inclamo::Support::Conflict unless existing.body == params['body'].to_s.strip && existing.uploads.pluck(:reference).sort == Array(params['files']).sort
  end

  def context(value)
    browser = value['browser'].to_s.first(200).gsub(/[\r\n]/, '')
    location = %w[conversation inbox settings contacts reports workspace].include?(value['location']) ? value['location'] : 'workspace'
    result = { 'version' => File.read(Rails.root.join('custom/INCLAMO_VERSION')).strip,
               'chatwoot_version' => File.read(Rails.root.join('VERSION_CW')).strip, 'timestamp' => Time.current.iso8601,
               'browser' => browser, 'location' => location }
    reference = value['conversation_reference'].to_s
    result['conversation_reference'] = reference if reference.match?(/\A\d{1,15}\z/)
    result
  end

  def download_url(request, id)
    "/api/v1/accounts/#{@member.account_id}/inclamo/support/requests/#{request.reference}/attachments/#{id}"
  end

  def local_download_url(request, reference)
    "/api/v1/accounts/#{@member.account_id}/inclamo/support/requests/#{request.reference}/uploads/#{reference}"
  end
end
