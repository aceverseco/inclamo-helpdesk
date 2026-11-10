# frozen_string_literal: true

# The agent's "Run" in the confirmation of a macro with order steps. Kept a
# short while for the run that follows; without it the dashboard's run of the
# macro runs nothing (see Inclamo::Shopify::MacroSteps::ExecutionGuard).
class Api::V1::Accounts::Inclamo::MacroConfirmationsController < Api::V1::Accounts::Conversations::BaseController
  # POST .../inclamo/macro_confirmations  { macro_id, conversation_id, digest }
  # `digest` comes with the preview the agent saw; a macro changed since is refused.
  def create
    macro = Current.account.macros.find_by(id: params[:macro_id])
    return head :not_found unless macro

    authorize macro, :execute?
    confirmation = ::Inclamo::Shopify::MacroSteps::Confirmation.new(macro: macro, conversation: @conversation, user: Current.user)
    return render json: { error: 'macro_changed' }, status: :conflict unless confirmation.give!(params[:digest])

    head :no_content
  end
end
