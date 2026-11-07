# frozen_string_literal: true

# Order actions from a conversation's panel. Whether the agent may act and
# whether the store allows it is decided on the server for every request.
class Api::V1::Accounts::Inclamo::OrderActionsController < Api::V1::Accounts::Conversations::BaseController
  # POST .../actions  { action_name, action_id, order_id, params: {...}, address: {...} }
  def create
    record = runner.perform(
      action: params[:action_name], action_id: params[:action_id], order_id: params[:order_id],
      params: params[:params].respond_to?(:to_unsafe_h) ? params[:params].to_unsafe_h : {},
      extra: { address: params[:address].respond_to?(:to_unsafe_h) ? params[:address].to_unsafe_h : nil }
    )
    render json: record.as_json, status: status_for(record)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render json: { error: 'invalid_request', message: e.message.first(200) }, status: :unprocessable_entity
  end

  # GET .../actions   every attempt made from this conversation, newest first
  def index
    records = ::Inclamo::OrderAction.where(account_id: Current.account.id, conversation_id: @conversation.id).order(id: :desc).limit(100)
    render json: { actions: records.map(&:as_json) }
  end

  # GET .../actions/:id   (id is the action id)
  def show
    record = ::Inclamo::OrderAction.find_by(account_id: Current.account.id, conversation_id: @conversation.id, action_id: params[:id])
    return head :not_found unless record

    render json: record.as_json
  end

  # POST .../actions/refund_preview  { order_id, params: {...} }
  def refund_preview
    preview = runner.refund_preview(order_id: params[:order_id], params: params[:params].respond_to?(:to_unsafe_h) ? params[:params].to_unsafe_h : {})
    render json: preview
  rescue ::Inclamo::Shopify::Actions::Refused, ::Inclamo::Shopify::Error => e
    refused = ::Inclamo::Shopify::OrderActionRunner.refusal_for(e)
    status = if refused[:reason] then :bad_gateway
             elsif refused[:refusal] == 'not_allowed' then :forbidden
             else :unprocessable_entity
             end
    render json: { error: refused[:refusal], message: refused[:message], reason: refused[:reason] }.compact, status: status
  end

  private

  def runner
    ::Inclamo::Shopify::OrderActionRunner.new(account: Current.account, account_user: Current.account_user, conversation: @conversation)
  end

  def status_for(record)
    return :forbidden if record.refusal == 'not_allowed'
    return :unprocessable_entity if record.outcome == 'refused'

    record.outcome == 'accepted' ? :ok : :accepted
  end
end
