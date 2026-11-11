# frozen_string_literal: true

require 'digest'

class Inclamo::WebsiteWidget::Configuration
  class Conflict < StandardError; end
  NATIVE_CHANNEL = %w[widget_color welcome_title welcome_tagline reply_time].freeze
  NATIVE_INBOX = %w[name portal_id].freeze

  def initialize(inbox)
    @inbox = inbox
    raise ActiveRecord::RecordNotFound unless inbox.web_widget?
  end

  def read
    record = Inclamo::WebsiteWidget.find_by(inbox: @inbox)
    {
      revision: revision(record),
      settings: Inclamo::WebsiteWidget.defaults(@inbox.account.locale).merge(record&.settings || {}),
      native: @inbox.attributes.slice(*NATIVE_INBOX).merge(@inbox.channel.attributes.slice(*NATIVE_CHANNEL)),
      avatar_url: @inbox.avatar_url,
      icon_url: record&.launcher_image&.attached? ? record.public_config['icon_url'] : nil,
      public: record ? record.public_config : Inclamo::WebsiteWidget.defaults(@inbox.account.locale),
      website_token: @inbox.channel.website_token,
      portals: @inbox.account.portals.order(:name).map { |portal| portal.attributes.slice('id', 'name', 'slug', 'config') },
      articles: @inbox.account.articles.published.order(:title).map { |article| article.attributes.slice('id', 'title', 'portal_id', 'slug') },
      locales: I18n.available_locales.map(&:to_s),
      channel: channel_preview
    }
  end

  def save!(data)
    invalid!('Invalid configuration object') unless data.is_a?(Hash) && (data.keys - %w[revision settings native icon_image remove_icon avatar_image remove_avatar]).empty?
    invalid!('Settings are required') unless data['settings'].is_a?(Hash)
    native = data.fetch('native', {})
    invalid!('Invalid native settings') unless native.is_a?(Hash) && (native.keys - NATIVE_CHANNEL - NATIVE_INBOX).empty?
    icon = Inclamo::WebsiteWidget::Image.decode(data['icon_image']) if data['icon_image']
    avatar = Inclamo::WebsiteWidget::Image.decode(data['avatar_image']) if data['avatar_image']
    invalid!('Header logo: use PNG, JPEG or WebP. SVG is supported for the chat icon.') if avatar && avatar[:content_type] == 'image/svg+xml'
    @inbox.with_lock do
      channel = @inbox.channel
      channel.lock!
      record = Inclamo::WebsiteWidget.find_or_initialize_by(inbox: @inbox)
      raise Conflict unless data['revision'].is_a?(String) && data['revision'] == revision(record.persisted? ? record : nil)
      if native.key?('portal_id') && native['portal_id'].present?
        @inbox.account.portals.find(native['portal_id'])
      end
      @inbox.assign_attributes(native.slice(*NATIVE_INBOX))
      channel.assign_attributes(native.slice(*NATIVE_CHANNEL))
      validate_native!(channel)
      record.account = @inbox.account
      record.inbox = @inbox # Validate article choices against the portal in this publication.
      record.settings = data['settings']
      record.validate!
      @inbox.validate!
      channel.validate!
      # Only a fully validated publication can update shared native fields/assets.
      record.launcher_image = icon if icon
      record.launcher_image = nil if data['remove_icon'] == true
      @inbox.avatar = avatar if avatar
      @inbox.avatar = nil if data['remove_avatar'] == true
      channel.save!
      @inbox.save!
      record.publication_version += 1
      record.save!
    end
    @inbox.reload
    read
  end

  def channel_preview
    channel = @inbox.channel
    {
      avatarUrl: @inbox.avatar_url, websiteName: @inbox.name, websiteToken: '', locale: @inbox.account.locale,
      welcomeTitle: channel.welcome_title, welcomeTagline: channel.welcome_tagline, widgetColor: channel.widget_color,
      enabledFeatures: channel.selected_feature_flags, enabledLanguages: I18n.available_locales.map { |locale| { iso_639_1_code: locale.to_s } },
      replyTime: channel.reply_time, preChatFormEnabled: channel.pre_chat_form_enabled, preChatFormOptions: channel.pre_chat_form_options,
      workingHoursEnabled: false, workingHours: [], timezone: @inbox.timezone, utcOffset: '+00:00',
      allowMessagesAfterResolved: @inbox.allow_messages_after_resolved, disableBranding: false, portal: nil
    }
  end

  private

  def revision(record)
    # Fingerprint shared values, not updated_at: background image analysis touches
    # records without editing configuration. Every editor publication advances its
    # own version, while changes through the native form still invalidate a draft.
    values = [@inbox.attributes.slice(*NATIVE_INBOX), @inbox.channel.attributes.slice(*NATIVE_CHANNEL), record&.publication_version,
              @inbox.avatar_attachment&.blob_id, record&.launcher_image_attachment&.blob_id]
    Digest::SHA256.hexdigest(values.to_json)
  end

  def validate_native!(channel)
    invalid!('Color must use #RGB or #RRGGBB') unless channel.widget_color.to_s.match?(/\A#(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i)
    Inclamo::WebsiteWidget::Settings.text!(channel.welcome_title.to_s, 'Welcome heading', 120, blank: true)
    Inclamo::WebsiteWidget::Settings.text!(channel.welcome_tagline.to_s, 'Welcome tagline', 255, blank: true)
  end

  def invalid!(message)
    raise Inclamo::WebsiteWidget::Settings::Invalid, message
  end
end
