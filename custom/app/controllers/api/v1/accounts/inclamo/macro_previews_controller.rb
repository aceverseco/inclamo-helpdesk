# frozen_string_literal: true

# What the order steps of a macro would do in a conversation, for the
# confirmation the dashboard shows before the macro runs. Open to whoever may
# see the conversation and run the macro. Every step is checked again when it
# runs; the agent's "Run" is recorded by MacroConfirmationsController.
class Api::V1::Accounts::Inclamo::MacroPreviewsController < Api::V1::Accounts::Conversations::BaseController
  # POST .../inclamo/macro_previews  { macro_id, conversation_id }
  def create
    macro = Current.account.macros.find_by(id: params[:macro_id])
    return head :not_found unless macro

    authorize macro, :execute?
    render json: ::Inclamo::Shopify::MacroSteps::Preview.new(macro: macro, conversation: @conversation, account_user: Current.account_user)
  end
end
