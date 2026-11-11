# frozen_string_literal: true

require 'vips'

module Inclamo::Support::Files
  TYPES = %w[image/png image/jpeg image/webp application/pdf text/plain].freeze
  module_function

  def validate!(bytes, filename:)
    raise Inclamo::Support::Invalid, 'file_size' if bytes.empty? || bytes.bytesize > Inclamo::Support::MAX_BYTES

    type = Marcel::MimeType.for(StringIO.new(bytes), name: filename)
    raise Inclamo::Support::Invalid, 'file_type' unless TYPES.include?(type)

    if type.start_with?('image/')
      image = Vips::Image.new_from_buffer(bytes, '', access: :sequential)
      raise Inclamo::Support::Invalid, 'image_dimensions' if image.width > 16384 || image.height > 16384 || image.width * image.height > 40_000_000
      # Re-encode: strip metadata/trailing content and retain only final pixels.
      bytes = image.write_to_buffer('.png', strip: true)
      type = 'image/png'
      filename = "#{File.basename(filename.to_s, '.*')}.png"
    elsif type == 'text/plain'
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      raise Inclamo::Support::Invalid, 'file_type' unless text.valid_encoding? && !text.include?("\x00")
      raise Inclamo::Support::Invalid, 'file_type' if text.match?(/<\s*(?:!doctype|html|svg|script|iframe)\b/i)
    elsif !bytes.start_with?('%PDF-')
      raise Inclamo::Support::Invalid, 'file_type'
    end
    raise Inclamo::Support::Invalid, 'file_size' if bytes.bytesize > Inclamo::Support::MAX_BYTES

    { bytes: bytes, type: type, filename: File.basename(filename.to_s).gsub(/[^a-zA-Z0-9._ -]/, '_').first(120).presence || 'attachment' }
  rescue Vips::Error
    raise Inclamo::Support::Invalid, 'file_type'
  end

  def stage!(bytes:, filename:, owner:, reference: SecureRandom.uuid)
    raise Inclamo::Support::Invalid, 'invalid_reference' unless reference.match?(Inclamo::Support::UUID)

    safe = validate!(bytes, filename: filename)
    checksum = Digest::SHA256.hexdigest(safe[:bytes])
    existing = Inclamo::Support::Upload.find_by(reference: reference, **owner)
    if existing
      raise Inclamo::Support::Conflict unless existing.checksum == checksum

      # Storage writes can fail after the database commits an attachment. Replay
      # restores the same blob key before retrying the receipt; no second issue.
      blob = existing.file.blob
      blob.service.upload(blob.key, StringIO.new(safe[:bytes]), checksum: blob.checksum) unless blob.service.exist?(blob.key)
      return existing
    end
    upload = Inclamo::Support::Upload.new(reference: reference, checksum: checksum, **owner)
    upload.file.attach(io: StringIO.new(safe[:bytes]), filename: safe[:filename], content_type: safe[:type], identify: false)
    upload.save!
    upload
  end

  def describe(upload)
    { reference: upload.reference, filename: upload.file.filename.to_s, size: upload.file.byte_size, type: upload.file.content_type }
  end

  def clean_staging!
    Inclamo::Support::Upload.where(submission_id: nil, receipt_id: nil).where(created_at: ...24.hours.ago).find_each do |upload|
      upload.file.purge
      upload.destroy!
    end
    Inclamo::Support::Throttle.where(expires_at: ...Time.current).delete_all
  end
end
