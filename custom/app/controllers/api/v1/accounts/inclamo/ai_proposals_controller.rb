# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::AiProposalsController < Api::V1::Accounts::Conversations::BaseController
  rescue_from ::Inclamo::Ai::OrderAuthority::Refused, with: :refused
  rescue_from ::Inclamo::Shopify::Error, with: :store_failed

  def index
    rows = ::Inclamo::AiProposal.where(account_id: Current.account.id, conversation_id: @conversation.id).order(id: :desc).limit(30)
    render json: { proposals: rows.map { |row| row.present(member: Current.account_user) } }
  end

  def approve
    render_proposal authority.execute(proposal, digest: params[:review_digest])
  end

  def reject
    render_proposal authority.reject(proposal)
  end

  def refresh
    render_proposal authority.refresh(proposal)
  end

  def verify_identity
    render_proposal authority.verify_identity(proposal)
  end

  private

  def proposal
    ::Inclamo::AiProposal.find_by!(id: params[:id], account_id: Current.account.id, conversation_id: @conversation.id)
  end

  def authority
    ::Inclamo::Ai::OrderAuthority.new(account: Current.account, conversation: @conversation, member: Current.account_user)
  end

  def render_proposal(record)
    render json: record.present(member: Current.account_user)
  end

  def refused(error)
    render json: { error: error.message }, status: error.message == 'not_allowed' ? :forbidden : :conflict
  end

  def store_failed(_error)
    render json: { error: 'store_unavailable' }, status: :bad_gateway
  end
end
