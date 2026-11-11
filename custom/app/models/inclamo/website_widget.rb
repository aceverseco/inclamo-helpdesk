# frozen_string_literal: true

class Inclamo::WebsiteWidget < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  has_one_attached :launcher_image

  validate :website_in_account
  validate :valid_settings

  def self.defaults(locale)
    {
      'position' => 'right', 'type' => 'standard', 'launcher_title' => '', 'icon' => 'chat',
      'offset_x' => 20, 'offset_y' => 20, 'theme' => 'light', 'language_mode' => 'fixed', 'locale' => locale,
      'visibility' => { 'mode' => 'all', 'rules' => [] }, 'starters' => [], 'links' => []
    }
  end

  def public_config
    value = self.class.defaults(account.locale).merge(settings)
    value['links'] = value['links'].select { |link| link['enabled'] }.filter_map do |link|
      if link['kind'] == 'article'
        article = inbox.portal&.articles&.published&.find_by(id: link['article_id'])
        next unless article

        link.merge('url' => "/hc/#{inbox.portal.slug}/articles/#{article.slug}")
      else
        link
      end
    end
    value['starters'] = value['starters'].select { |entry| entry['enabled'] }
    if launcher_image.attached?
      value['icon_url'] = Inclamo::WebsiteWidget::Image.url(launcher_image)
    end
    value
  end

  def self.for_public(inbox)
    record = find_by(inbox_id: inbox.id)
    return {} unless record

    Inclamo::WebsiteWidget::Settings.validate!(record.settings, inbox: inbox, check_articles: false)
    record.public_config
  rescue Inclamo::WebsiteWidget::Settings::Invalid
    {}
  end

  private

  def website_in_account
    errors.add(:inbox, 'must be a website in this account') unless inbox&.web_widget? && inbox.account_id == account_id
  end

  def valid_settings
    Inclamo::WebsiteWidget::Settings.validate!(settings, inbox: inbox)
  rescue Inclamo::WebsiteWidget::Settings::Invalid => e
    errors.add(:settings, e.message)
  end
end
