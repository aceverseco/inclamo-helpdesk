# frozen_string_literal: true

# Inclamo Helpdesk: the one file placed in Chatwoot's config/initializers.
# It only hands over to the overlay in custom/; all logic lives there.
overlay = Rails.root.join('custom/config/overlay.rb')
load overlay.to_s if overlay.exist?
