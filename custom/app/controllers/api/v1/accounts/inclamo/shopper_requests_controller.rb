# frozen_string_literal: true

# The ticket of a request about one shopper (capability app-store-erasure), as
# its card in the conversation shows it, and the card's actions. Only the
# account's administrators: the overlay's own check, whatever inbox the user
# can see. While the request is not done the card shows the shopper's email
# and phone as Shopify gave them and the account's contacts that match them
# now; afterwards neither.
class Api::V1::Accounts::Inclamo::ShopperRequestsController < Api::V1::Accounts::BaseController
  include ::Inclamo::RequireAdministrator
  require_administrator 'inclamo.erasure.errors.forbidden'
  before_action :find_request

  def show
    render json: present
  end

  # POST delete: deletes the shopper's data now (an erasure, waiting or held).
  def erase
    act { ::Inclamo::Erasure::ShopperActions.delete!(@shopper_request, Current.user) }
  end

  # POST hold { reason }: stops the automatic deletion (an erasure, waiting).
  def hold
    act { ::Inclamo::Erasure::ShopperActions.hold!(@shopper_request, Current.user, params[:reason]) }
  end

  # POST lift: the automatic deletion is due again on its date (an erasure, held).
  def lift
    act { ::Inclamo::Erasure::ShopperActions.lift!(@shopper_request, Current.user) }
  end

  # POST answered: the team has answered the shopper (a data request, waiting).
  def answered
    act { ::Inclamo::Erasure::ShopperActions.answered!(@shopper_request, Current.user) }
  end

  private

  def find_request
    @shopper_request = ::Inclamo::ErasureRequest.shoppers.find_by(id: params[:id], account_id: Current.account.id)
    head :not_found unless @shopper_request
  end

  def act
    yield
    render json: present
  rescue ::Inclamo::Erasure::ShopperActions::WrongState => e
    render json: { error: 'wrong_state', state: e.state }, status: :conflict
  rescue ::Inclamo::Erasure::ShopperActions::ReasonMissing
    render json: { error: 'reason_missing' }, status: :unprocessable_entity
  rescue ::Inclamo::Erasure::Journal::Unwritable => e
    Rails.logger.error("[inclamo erasure] ALERT #{e.message}; request #{@shopper_request.id} was not done")
    render json: { error: 'not_done' }, status: :service_unavailable
  end

  def present
    ::Inclamo::Erasure::TicketCard.new(@shopper_request.reload).as_json
  end
end
