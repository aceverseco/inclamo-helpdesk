# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::WebsiteWidgetsController < Api::V1::Accounts::BaseController
  before_action :require_administrator
  before_action :find_inbox

  rescue_from ::Inclamo::WebsiteWidget::Settings::Invalid, ::Inclamo::WebsiteWidget::Image::Invalid, ActiveRecord::RecordInvalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from ::Inclamo::WebsiteWidget::Configuration::Conflict do
    render json: { error: 'Another administrator changed these settings. Reload the saved version before publishing again.' }, status: :conflict
  end

  def show
    response.headers['Cache-Control'] = 'no-store'
    render json: service.read
  end

  def update
    raise ::Inclamo::WebsiteWidget::Settings::Invalid, 'Configuration is required' unless params[:configuration].is_a?(ActionController::Parameters)

    render json: service.save!(params[:configuration].to_unsafe_h)
  end

  def preview
    response.headers['Cache-Control'] = 'no-store'
    @channel_preview = service.channel_preview
    @preview_branding = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'INSTALLATION_NAME')
    render template: 'inclamo/website_widget_preview', layout: false, formats: [:html]
  end

  private

  def find_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @inbox.web_widget?
  end

  def service
    @service ||= ::Inclamo::WebsiteWidget::Configuration.new(@inbox)
  end

  def require_administrator
    head :forbidden unless Current.account_user&.administrator?
  end
end
