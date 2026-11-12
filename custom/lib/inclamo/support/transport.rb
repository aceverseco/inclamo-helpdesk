# frozen_string_literal: true

require 'net/http'

class Inclamo::Support::Transport
  def initialize
    @installation = Inclamo::Support::Installation.identity
  end

  def enroll!
    @installation.with_lock do
      endpoint = Inclamo::Support.endpoint
      raise Inclamo::Support::Unavailable if endpoint.blank?

      Inclamo::Support.valid_url!(endpoint)
      raise Inclamo::Support::Conflict if @installation.endpoint.present? && @installation.endpoint != endpoint
      return if @installation.source_id.present?

      result = call('POST', 'register', { public_key: @installation.public_key, base_url: Inclamo::Support.base_url }, enroll: true)
      @installation.update!(source_id: result.fetch('source_id'), endpoint: endpoint)
    end
  end

  def deliver!(submission)
    enroll!
    request = submission.request
    member = AccountUser.find_by(account_id: request.account_id, user_id: submission.actor_id)
    raise Inclamo::Support::Unauthorized unless request.accessible_by?(member)

    staged = submission.staged_files.dup
    submission.uploads.order(:id).each do |upload|
      # The deterministic file UUID and same content make a lost upload ack safe.
      response = call('POST', 'uploads', { reference: upload.reference, filename: upload.file.filename.to_s,
                                            bytes: Base64.strict_encode64(upload.file.download) })
      staged[upload.reference] = response.fetch('reference')
      submission.update!(staged_files: staged)
    end
    payload = { uuid: submission.uuid, request_reference: request.reference, account_key: "account:#{request.account_id}",
                initial: request.submissions.order(:id).first.id == submission.id, category: request.category,
                author: request.author_snapshot, actor: submission.actor_snapshot, context: request.context,
                body: submission.body, files: submission.uploads.order(:id).map { |upload| staged.fetch(upload.reference) } }
    result = call('POST', 'submissions', payload)
    request.update!(central_reference: result.fetch('reference'))
    state = result.fetch('state')
    raise Inclamo::Support::Unavailable unless %w[delivered attachments_pending].include?(state)

    submission.update!(state: state, central_message_id: result.fetch('message_id'), error_code: state == 'delivered' ? nil : 'attachments_incomplete',
                       lease_until: nil, next_attempt_at: state == 'delivered' ? nil : 30.seconds.from_now)
    result
  end

  def events(cursor)
    enroll!
    call('GET', "events?cursor=#{Integer(cursor)}")
  end

  def reconcile(request)
    return unless request.central_reference

    enroll!
    call('POST', "requests/#{request.central_reference}/reconcile", {})
  end

  def download(request, file_id)
    raise Inclamo::Support::Unauthorized unless request.central_reference && file_id.to_s.match?(/\A\d{1,20}\z/)

    enroll!
    call('GET', "requests/#{request.central_reference}/attachments/#{file_id}", nil, binary: true)
  end

  def recipient(request, member, verify:, code: nil)
    enroll!
    identity = { account_key: "account:#{request.account_id}", actor_key: request.author_key }
    if verify
      call('POST', 'recipients/verify', identity.merge(code: code))
    else
      enabled = Inclamo::Support::NotificationPreference.enabled_for?(member)
      call('POST', 'recipients', { recipients: [identity.merge(email: member.user.email, active: enabled,
                                                              locally_verified: member.user.confirmed?, request_verification: enabled)] })
    end
  end

  def sync_recipients
    authors = Inclamo::Support::Request.distinct.pluck(:account_id, :author_id, :author_key)
    authors.each_slice(100) do |batch|
      recipients = batch.map do |account_id, author_id, author_key|
        member = AccountUser.find_by(account_id: account_id, user_id: author_id)
        { account_key: "account:#{account_id}", actor_key: author_key,
          email: member&.user&.email, active: Inclamo::Support::NotificationPreference.enabled_for?(member), locally_verified: member&.user&.confirmed? || false }
      end
      call('POST', 'recipients', { recipients: recipients })
    end
  end

  def call(method, path, payload = nil, enroll: false, binary: false)
    endpoint = @installation.endpoint.presence || Inclamo::Support.endpoint
    Inclamo::Support.valid_url!(endpoint)
    uri = URI.parse("#{endpoint}/#{path}")
    body = payload ? JSON.generate(payload) : ''
    timestamp = Time.now.to_i.to_s
    request = Net::HTTPGenericRequest.new(method, method != 'GET', true, uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['X-Inclamo-Source'] = @installation.source_id unless enroll
    request['X-Inclamo-Timestamp'] = timestamp
    request['X-Inclamo-Signature'] = Inclamo::Support::Authentication.sign(@installation.private_key, method, uri.request_uri, timestamp, body)
    request.body = body unless method == 'GET'
    response_body = +''
    result = nil
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 20
    http.write_timeout = 20
    http.request(request) do |response|
      response.read_body do |chunk|
        response_body << chunk
        raise Inclamo::Support::Unavailable if response_body.bytesize > (binary ? Inclamo::Support::MAX_BYTES : 8 * 1024 * 1024)
      end
      raise Inclamo::Support::Conflict if response.code == '409'
      raise Inclamo::Support::Rejected if %w[401 403 404].include?(response.code)
      raise Inclamo::Support::Unavailable unless response.is_a?(Net::HTTPSuccess)

      result = if binary
                 type = response['content-type'].to_s.split(';').first
                 raise Inclamo::Support::Invalid, 'file_type' unless Inclamo::Support::Files::TYPES.include?(type)

                 { bytes: response_body, type: type, filename: 'support-attachment' }
               else
                 JSON.parse(response_body)
               end
    end
    result
  rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, JSON::ParserError
    raise Inclamo::Support::Unavailable
  end
end
