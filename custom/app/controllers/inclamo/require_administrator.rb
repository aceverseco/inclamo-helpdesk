# frozen_string_literal: true

# Endpoints of the overlay that only the account's administrators may use;
# anyone else gets 403 with the controller's own message:
#
#   include ::Inclamo::RequireAdministrator
#   require_administrator 'inclamo.sla.errors.forbidden'
module Inclamo::RequireAdministrator
  extend ActiveSupport::Concern

  class_methods do
    def require_administrator(message_key)
      before_action { refuse_unless_administrator(message_key) }
    end
  end

  private

  def refuse_unless_administrator(message_key)
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden', message: I18n.t(message_key) }, status: :forbidden
  end
end
