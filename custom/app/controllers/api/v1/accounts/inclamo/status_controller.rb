# frozen_string_literal: true

# Tells a signed-in member of the account that the overlay is present and
# which versions it runs. The dashboard uses it to decide whether to show the
# overlay's sections.
class Api::V1::Accounts::Inclamo::StatusController < Api::V1::Accounts::BaseController
  def show
    render json: {
      overlay_version: ::Inclamo::Overlay.version,
      chatwoot_version: ::Inclamo::Overlay.chatwoot_version,
      migrations_pending: ::Inclamo::Overlay::Migrations.pending?
    }
  end
end
