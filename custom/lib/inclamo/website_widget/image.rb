# frozen_string_literal: true

require 'base64'
require 'stringio'
require 'vips'

class Inclamo::WebsiteWidget::Image
  class Invalid < StandardError; end
  ELEMENTS = %w[svg g path rect circle ellipse line polyline polygon defs linearGradient radialGradient stop title desc].freeze
  ATTRIBUTES = %w[xmlns viewBox width height x y x1 x2 y1 y2 cx cy r rx ry d points fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin stroke-opacity opacity transform id offset stop-color stop-opacity gradientUnits gradientTransform spreadMethod].freeze

  def self.decode(value)
    raise Invalid, 'Invalid image' unless value.is_a?(Hash) && value['data'].is_a?(String) && value['data'].bytesize <= 1_400_000
    bytes = Base64.strict_decode64(value['data'])
    raise Invalid, 'Image must be 1 MB or smaller' if bytes.bytesize > 1_048_576 || bytes.empty?
    type = Marcel::MimeType.for(StringIO.new(bytes))
    if type == 'image/svg+xml' || bytes.lstrip.start_with?('<svg', '<?xml')
      bytes = sanitize_svg(bytes)
      type = 'image/svg+xml'
    else
      raise Invalid, 'Use PNG, JPEG, WebP or a safe SVG' unless %w[image/png image/jpeg image/webp].include?(type)
      decode_pixels(bytes)
    end
    extension = { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/svg+xml' => 'svg' }.fetch(type)
    { io: StringIO.new(bytes), filename: "widget-image.#{extension}", content_type: type,
      metadata: { inclamo_widget_validated: true }, identify: false }
  rescue ArgumentError
    raise Invalid, 'Invalid image encoding'
  rescue Vips::Error
    raise Invalid, 'Image could not be decoded'
  end

  def self.decode_pixels(bytes)
    image = Vips::Image.new_from_buffer(bytes, '')
    raise Invalid, 'Image dimensions must be between 1 and 4096 pixels' unless image.width.between?(1, 4096) && image.height.between?(1, 4096)
    image.avg # Decode pixels, not just a claimed header.
    image
  end

  def self.url(attachment)
    return unless attachment.attached?

    # Active Storage deliberately downloads arbitrary SVG uploads. Only images
    # that passed this validator get the narrowly scoped, signed inline route.
    if attachment.blob.content_type == 'image/svg+xml' && attachment.blob.metadata['inclamo_widget_validated'] == true
      id = attachment.blob.signed_id(purpose: 'inclamo_widget_image')
      "/inclamo/widget-images/#{id}"
    else
      Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true, disposition: 'inline')
    end
  end

  def self.sanitize_svg(bytes)
    raise Invalid, 'SVG external declarations are not allowed' if bytes.match?(/<!DOCTYPE|<!ENTITY|<\?xml-stylesheet/i)
    document = Nokogiri::XML(bytes) { |config| config.strict.nonet }
    raise Invalid, 'Invalid SVG root' unless document.root&.name == 'svg'
    document.traverse do |node|
      next unless node.element?
      raise Invalid, 'SVG contains unsupported active content' unless ELEMENTS.include?(node.name)
      node.attribute_nodes.each do |attr|
        unless ATTRIBUTES.include?(attr.name) && !attr.value.match?(/url\(|javascript:|data:|https?:|\/\//i)
          raise Invalid, 'SVG contains an unsafe attribute or external reference'
        end
      end
    end
    document.root.to_xml
  rescue Nokogiri::XML::SyntaxError
    raise Invalid, 'Invalid SVG document'
  end
end
