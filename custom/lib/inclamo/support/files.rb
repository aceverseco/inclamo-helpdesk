# frozen_string_literal: true

require 'vips'

module Inclamo::Support::Files
  TYPES = %w[image/png image/jpeg image/webp application/pdf text/plain].freeze
  # How an image is written again: format, options, file extension.
  IMAGE_SAVERS = { 'image/png' => ['.png', {}, '.png'], 'image/jpeg' => ['.jpg', { Q: 92 }, '.jpg'], 'image/webp' => ['.webp', { Q: 92 }, '.webp'] }.freeze
  module_function

  def validate!(bytes, filename:)
    raise Inclamo::Support::Invalid, 'file_size' if bytes.empty? || bytes.bytesize > Inclamo::Support::MAX_BYTES

    type = Marcel::MimeType.for(StringIO.new(bytes), name: filename)
    raise Inclamo::Support::Invalid, 'file_type' unless TYPES.include?(type)

    if type.start_with?('image/')
      bytes, type = rewrite_image(bytes, type)
      filename = "#{File.basename(filename.to_s, '.*')}#{IMAGE_SAVERS.fetch(type).last}"
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

  # The image is written again from its pixels, which drops its metadata and
  # anything appended after them. It keeps its own format: as PNG a photo grows
  # several times over, and a file under the displayed limit would be refused
  # for our re-encoding. One still over the limit is written once more as a
  # JPEG, on white where it was transparent.
  def rewrite_image(bytes, type)
    image = pixels(bytes)
    raise Inclamo::Support::Invalid, 'image_dimensions' if image.width > 16384 || image.height > 16384 || image.width * image.height > 40_000_000

    written = save_image(image, type)
    return [written, type] if written.bytesize <= Inclamo::Support::MAX_BYTES || type == 'image/jpeg'

    image = pixels(bytes) # read sequentially, an image is read only once
    image = image.flatten(background: [255]) if image.has_alpha?
    [save_image(image, 'image/jpeg'), 'image/jpeg']
  end

  def pixels(bytes)
    Vips::Image.new_from_buffer(bytes, '', access: :sequential)
  end

  def save_image(image, type)
    format, options, = IMAGE_SAVERS.fetch(type)
    image.write_to_buffer(format, strip: true, **options)
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
