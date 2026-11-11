# frozen_string_literal: true

# Public delivery for sanitized SVGs only. General Active Storage upload rules
# stay intact; a normal blob token cannot authorize this route.
class Inclamo::WidgetImagesController < ActionController::Base
  def show
    blob = ActiveStorage::Blob.find_signed!(params[:id], purpose: 'inclamo_widget_image')
    return head :not_found unless blob.content_type == 'image/svg+xml' && blob.metadata['inclamo_widget_validated'] == true
    return unless stale?(etag: blob.checksum, last_modified: blob.created_at, public: true)

    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox"
    expires_in 1.year, public: true, immutable: true
    send_data blob.download, type: 'image/svg+xml', disposition: 'inline', filename: 'widget-image.svg'
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError
    head :not_found
  end
end
