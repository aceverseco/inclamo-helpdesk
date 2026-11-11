# frozen_string_literal: true

class Inclamo::Support::Intake
  def initialize(source)
    @source = source
  end

  def submit!(payload)
    validate!(payload)
    digest = Digest::SHA256.hexdigest(canonical(payload).to_json)
    receipt = nil
    @source.with_lock do
      raise Inclamo::Support::Unauthorized if @source.revoked_at

      receipt = Inclamo::Support::Receipt.find_by(source_id: @source.id, uuid: payload['uuid'])
      if receipt
        raise Inclamo::Support::Conflict unless receipt.digest == digest

        repair_attachments!(receipt)
        return result(receipt)
      end
      uploads = uploads!(payload)
      mapping = @source.requests.find_by(local_reference: payload['request_reference'])
      if mapping
        raise Inclamo::Support::Unauthorized unless mapping.account_key == payload['account_key'] && mapping.author_key == payload['author']['key']
        raise Inclamo::Support::Unauthorized unless payload['actor']['key'] == mapping.author_key || payload['actor']['administrator'] == true
      else
        raise Inclamo::Support::Invalid, 'request_not_delivered' unless payload['initial'] == true && payload['actor']['key'] == payload['author']['key']

        mapping = create_request!(payload)
      end
      actor = contact(payload['account_key'], payload['actor'])
      content = message_content(payload, mapping)
      params = ActionController::Parameters.new(content: content, message_type: 'incoming', private: false,
                                               source_id: "inclamo-support:#{@source.reference}:#{payload['uuid']}",
                                               content_attributes: { inclamo_support_actor: payload['actor'].slice('key', 'name', 'administrator'),
                                                                     inclamo_support_submission: payload['uuid'] },
                                               attachments: uploads.map { |upload| upload.file.blob.signed_id })
      message = Messages::MessageBuilder.new(actor.contact, mapping.conversation, params).perform
      # The API-inbox builder defaults all incoming senders to the conversation's
      # contact. Preserve the actual administrator contact before the transaction commits.
      message.update!(sender: actor.contact) unless message.sender == actor.contact
      receipt = Inclamo::Support::Receipt.create!(source: @source, central_request: mapping,
                                                 uuid: payload['uuid'], digest: digest, message: message)
      uploads.each { |upload| upload.update!(receipt_id: receipt.id) }
    end
    Inclamo::Support::ReconcileJob.perform_later(receipt.central_request_id)
    result(receipt)
  end

  def result(receipt)
    files = receipt.message.attachments.includes(file_attachment: :blob).to_a
    expected = Inclamo::Support::Upload.where(receipt_id: receipt.id).includes(file_attachment: :blob).map { |upload| upload.file.blob_id }.sort
    actual = files.filter_map { |file| file.file.blob_id if file.file.attached? }.sort
    complete = actual == expected && files.all? { |file| file.file.attached? && file.file.blob.service.exist?(file.file.blob.key) }
    { reference: receipt.central_request.reference, message_id: receipt.message_id.to_s, state: complete ? 'delivered' : 'attachments_pending' }
  end

  private

  def repair_attachments!(receipt)
    message = receipt.message
    raise Inclamo::Support::Conflict unless message && Inclamo::Support::Feed.public?(message)

    attached = message.attachments.filter_map { |attachment| attachment.file.blob_id if attachment.file.attached? }
    changed = false
    Inclamo::Support::Upload.where(receipt_id: receipt.id).each do |upload|
      blob = upload.file.blob
      next if attached.include?(blob.id)

      message.attachments.create!(account_id: message.account_id, file: blob, file_type: blob.content_type.start_with?('image/') ? :image : :file)
      changed = true
    end
    message.touch if changed
    Inclamo::Support::ReconcileJob.perform_later(receipt.central_request_id) if changed
  end

  def canonical(value)
    case value
    when Hash then value.sort.to_h.transform_values { |child| canonical(child) }
    when Array then value.map { |child| canonical(child) }
    else value
    end
  end

  def validate!(payload)
    raise Inclamo::Support::Invalid, 'invalid_payload' unless payload.is_a?(Hash)
    %w[uuid request_reference].each { |key| raise Inclamo::Support::Invalid, 'invalid_reference' unless payload[key].to_s.match?(Inclamo::Support::UUID) }
    raise Inclamo::Support::Invalid, 'invalid_account' unless payload['account_key'].to_s.match?(/\Aaccount:\d{1,15}\z/)
    raise Inclamo::Support::Invalid, 'invalid_body' unless payload['body'].is_a?(String) && payload['body'].strip.present? && payload['body'].length <= Inclamo::Support::MAX_BODY
    raise Inclamo::Support::Invalid, 'invalid_category' unless %w[problem question suggestion].include?(payload['category'])
    %w[actor author].each do |key|
      actor = payload[key]
      raise Inclamo::Support::Invalid, 'invalid_actor' unless actor.is_a?(Hash) && actor['key'].to_s.match?(/\Auser:\d{1,15}\z/) && actor['name'].is_a?(String) && actor['name'].length <= 120
    end
    context = payload['context']
    raise Inclamo::Support::Invalid, 'invalid_context' unless context.is_a?(Hash) && context.to_json.bytesize <= 2000
    raise Inclamo::Support::Invalid, 'invalid_files' unless payload['files'].is_a?(Array) && payload['files'].size <= Inclamo::Support::MAX_FILES
  end

  def uploads!(payload)
    refs = payload['files']
    raise Inclamo::Support::Invalid, 'invalid_files' unless refs.uniq.size == refs.size

    uploads = Inclamo::Support::Upload.where(source_id: @source.id, reference: refs, receipt_id: nil).lock.to_a
    raise Inclamo::Support::Invalid, 'attachments_incomplete' unless uploads.size == refs.size && uploads.all? { |upload| upload.file.attached? && upload.created_at > 24.hours.ago }

    uploads
  end

  def contact(account_key, actor)
    identifier = "inclamo-support:#{Digest::SHA256.hexdigest([@source.reference, account_key, actor['key']].join(':'))}"
    ContactInboxWithContactBuilder.new(
      inbox: Inclamo::Support.inbox, source_id: identifier,
      contact_attributes: { identifier: identifier, name: actor['name'],
                            additional_attributes: { inclamo_support_source: @source.reference, inclamo_support_account: account_key } }
    ).perform
  end

  def create_request!(payload)
    inbox_contact = contact(payload['account_key'], payload['author'])
    origin = @source.hosted? ? 'hosted' : 'self_hosted'
    attributes = { inclamo_support_origin: origin, inclamo_support_source: @source.reference,
                   inclamo_support_account: payload['account_key'], inclamo_support_category: payload['category'],
                   inclamo_support_version: payload['context']['version'].to_s.first(80) }
    {
      'inclamo_support_origin' => 'Support installation type', 'inclamo_support_source' => 'Support source',
      'inclamo_support_account' => 'Originating account', 'inclamo_support_category' => 'Support category',
      'inclamo_support_version' => 'Reported app version'
    }.each do |key, label|
      CustomAttributeDefinition.find_or_create_by!(account_id: inbox_contact.inbox.account_id, attribute_model: :conversation_attribute, attribute_key: key) do |definition|
        definition.attribute_display_name = label
        definition.attribute_display_type = :text
        definition.attribute_description = 'Recorded by the Inclamo support intake.'
      end
    end
    conversation = ConversationBuilder.new(
      params: ActionController::Parameters.new(status: 'open', custom_attributes: attributes), contact_inbox: inbox_contact
    ).perform
    label = "inclamo-#{origin.tr('_', '-')}"
    Label.find_or_create_by!(account_id: conversation.account_id, title: label) { |record| record.color = '#6b5bd2' }
    conversation.add_labels([label])
    @source.requests.create!(reference: SecureRandom.uuid, local_reference: payload['request_reference'],
                             account_key: payload['account_key'], author_key: payload['author']['key'],
                             author: payload['author'].slice('key', 'name', 'email'), conversation: conversation)
  end

  def message_content(payload, mapping)
    actor = payload['actor']
    role = actor['administrator'] ? 'administrator' : 'author'
    heading = "#{actor['name']} (#{role})"
    return "#{heading}\n\n#{payload['body']}" unless payload['initial']

    origin = @source.hosted? ? 'Inclamo hosting' : 'Self-hosted'
    context = payload['context'].slice('version', 'chatwoot_version', 'timestamp', 'browser', 'location', 'conversation_reference')
    ["#{origin} · #{payload['category']} · #{mapping.reference}", heading,
     "Installation: #{@source.reference}\nAccount: #{mapping.account_key}", payload['body'],
     context.map { |key, value| "#{key}: #{value}" }.join("\n")].join("\n\n")
  end
end
