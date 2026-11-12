# frozen_string_literal: true

module Inclamo::Support::Recipients
  module_function

  def sync!(source, payload)
    entries = payload['recipients']
    raise Inclamo::Support::Invalid, 'invalid_recipients' unless entries.is_a?(Array) && entries.size <= 100

    results = entries.map do |entry|
      validate_identity!(entry)
      existing = Inclamo::Support::Recipient.find_by(source: source, account_key: entry['account_key'], actor_key: entry['actor_key'])
      if entry['active'] != true
        existing&.update!(active: false, verified_at: nil, verification_digest: nil)
        next { verified: false }
      end
      email = entry['email'].to_s.downcase
      raise Inclamo::Support::Invalid, 'invalid_email' unless email.length <= 254 && email.match?(URI::MailTo::EMAIL_REGEXP)

      recipient = existing || Inclamo::Support::Recipient.new(source: source, account_key: entry['account_key'], actor_key: entry['actor_key'])
      if recipient.email != email || !recipient.active?
        recipient.assign_attributes(email: email, active: true, verified_at: nil, verification_digest: nil)
      end
      if source.hosted?
        recipient.verified_at = entry['locally_verified'] == true ? (recipient.verified_at || Time.current) : nil
      end
      recipient.save!
      if entry['request_verification'] == true && !recipient.verified_at
        Inclamo::Support::Authentication.rate!("verification:#{recipient.id}", limit: 3, seconds: 3600)
        code = SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')
        recipient.update!(verification_digest: Digest::SHA256.hexdigest(code), verification_expires_at: 15.minutes.from_now, verification_attempts: 0)
        Inclamo::Support::Mailer.verification(recipient.email, code).deliver_now
      end
      { verified: recipient.verified_at.present?, email: recipient.email }
    end
    { recipients: results }
  end

  def verify!(source, payload)
    validate_identity!(payload)
    recipient = Inclamo::Support::Recipient.find_by!(source: source, account_key: payload['account_key'], actor_key: payload['actor_key'], active: true)
    valid = false
    recipient.with_lock do
      raise Inclamo::Support::Invalid, 'verification_expired' unless recipient.verification_expires_at&.future? && recipient.verification_attempts < 5

      recipient.verification_attempts += 1
      digest = Digest::SHA256.hexdigest(payload['code'].to_s)
      valid = recipient.verification_digest.present? && ActiveSupport::SecurityUtils.secure_compare(recipient.verification_digest, digest)
      recipient.assign_attributes(verified_at: Time.current, verification_digest: nil, verification_expires_at: nil) if valid
      recipient.save!
    end
    raise Inclamo::Support::Invalid, 'verification_invalid' unless valid

    { verified: true }
  end

  def notify!(mapping, message)
    recipient = Inclamo::Support::Recipient.find_by(source_id: mapping.source_id, account_key: mapping.account_key, actor_key: mapping.author_key, active: true)
    return unless recipient&.verified_at
    return if recipient.verified_at > message.created_at

    delivery = Inclamo::Support::Delivery.create_or_find_by!(recipient: recipient, message_id: message.id) do |record|
      record.central_request = mapping
    end
    Inclamo::Support::NotifyJob.perform_later(delivery.id) unless delivery.delivered_at
  end

  def validate_identity!(entry)
    raise Inclamo::Support::Invalid, 'invalid_identity' unless entry.is_a?(Hash) && entry['account_key'].to_s.match?(/\Aaccount:\d{1,15}\z/) && entry['actor_key'].to_s.match?(/\Auser:\d{1,15}\z/)
  end
end
