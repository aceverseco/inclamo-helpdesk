# frozen_string_literal: true

class Inclamo::WebsiteWidget::Settings
  class Invalid < StandardError; end

  ENUMS = {
    'position' => %w[left right], 'type' => %w[standard expanded_bubble],
    'icon' => %w[chat message help custom], 'theme' => %w[light dark auto], 'language_mode' => %w[fixed browser]
  }.freeze
  KEYS = (ENUMS.keys + %w[launcher_title offset_x offset_y locale visibility starters links]).freeze

  def self.validate!(settings, inbox:, check_articles: true)
    raise Invalid, 'Settings must be an object' unless settings.is_a?(Hash)
    raise Invalid, 'Unknown setting' if (settings.keys - KEYS).any?

    ENUMS.each { |key, allowed| raise Invalid, "Invalid #{key}" if settings.key?(key) && !allowed.include?(settings[key]) }
    %w[offset_x offset_y].each do |key|
      next unless settings.key?(key)
      raise Invalid, "#{key} must be between 0 and 160" unless settings[key].is_a?(Integer) && settings[key].between?(0, 160)
    end
    text!(settings['launcher_title'], 'Launcher title', 60, blank: true) if settings.key?('launcher_title')
    if settings.key?('locale') && !I18n.available_locales.map(&:to_s).include?(settings['locale'])
      raise Invalid, 'Unsupported language'
    end
    visibility!(settings['visibility']) if settings.key?('visibility')
    entries!(settings.fetch('starters', []), :starters, inbox, check_articles)
    entries!(settings.fetch('links', []), :links, inbox, check_articles)
  end

  def self.text!(value, name, limit, blank: false)
    raise Invalid, "#{name} must be text up to #{limit} characters" unless value.is_a?(String) && value.length <= limit && (blank || value.strip.present?)
  end

  def self.visibility!(value)
    unless value.is_a?(Hash) && (value.keys - %w[mode rules]).empty? && %w[all include exclude].include?(value['mode']) && value['rules'].is_a?(Array) && value['rules'].size <= 20
      raise Invalid, 'Visibility requires a mode and up to 20 path rules'
    end
    value['rules'].each do |rule|
      unless rule.is_a?(Hash) && (rule.keys - %w[path match]).empty? && %w[exact prefix].include?(rule['match'])
        raise Invalid, 'Invalid page rule'
      end
      text!(rule['path'], 'Page path', 512)
      raise Invalid, 'Use a path starting with /, without query or fragment' unless rule['path'].start_with?('/') && !rule['path'].match?(/[?#\s]/)
    end
    raise Invalid, 'Include mode needs at least one path' if value['mode'] == 'include' && value['rules'].empty?
  end

  def self.entries!(entries, kind, inbox, check_articles)
    raise Invalid, "#{kind} must contain at most 30 entries" unless entries.is_a?(Array) && entries.size <= 30
    ids = []
    enabled = 0
    entries.each do |entry|
      keys = kind == :starters ? %w[id label message enabled] : %w[id label kind url article_id enabled]
      raise Invalid, "Invalid #{kind} entry" unless entry.is_a?(Hash) && (entry.keys - keys).empty?
      text!(entry['id'], 'Entry id', 80)
      raise Invalid, 'Duplicate entry id' if ids.include?(entry['id'])
      ids << entry['id']
      raise Invalid, 'Enabled must be true or false' unless [true, false].include?(entry['enabled'])
      enabled += 1 if entry['enabled']
      text!(entry['label'], 'Label', 60)
      if kind == :starters
        text!(entry['message'], 'Starter message', 500)
      elsif entry['kind'] == 'article'
        raise Invalid, 'Choose a published article' unless entry['article_id'].is_a?(Integer) && entry['article_id'].positive?
        raise Invalid, 'Choose a published article in the connected Help Center' if check_articles && !inbox&.portal&.articles&.published&.exists?(id: entry['article_id'])
      elsif entry['kind'] == 'url'
        uri = URI.parse(entry['url'].to_s)
        raise Invalid, 'Link must be an HTTPS URL without credentials' unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && entry['url'].length <= 2048
      else
        raise Invalid, 'Choose article or URL'
      end
    rescue URI::InvalidURIError
      raise Invalid, 'Invalid HTTPS link'
    end
    raise Invalid, "Enable at most six #{kind}" if enabled > 6
  end
end
