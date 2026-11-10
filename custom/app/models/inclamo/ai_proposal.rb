# frozen_string_literal: true

class Inclamo::AiProposal < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :agent_bot
  belongs_to :approved_by, class_name: 'User', optional: true
  encrypts :payload
  validates :request_id, format: { with: /\A[A-Za-z0-9-]{8,64}\z/ }, uniqueness: { scope: :account_id }
  validates :action, inclusion: { in: Inclamo::ActionPermissions::ACTIONS }
  validates :state, inclusion: { in: %w[proposed approved rejected accepted refused pending running unknown] }

  def data
    JSON.parse(payload)
  end

  def action_record
    Inclamo::OrderAction.find_by(account_id: account_id, ai_proposal_id: id)
  end

  def present(member: nil)
    record = action_record
    facts = data
    policy_allows = Inclamo::ActionPermissions.required(action, facts.dig('request', 'params') || {}).all? { |right| Inclamo::AiPolicy.for(account, right).mode != 'forbidden' }
    {
      id: id, request_id: request_id, action: action, state: record&.outcome || state, reason: reason,
      review_digest: review_digest, expires_at: expires_at, expired: expires_at <= Time.current,
      request: facts['request'], summary: facts['summary'],
      initiator: { id: agent_bot_id, name: agent_bot&.name },
      approver: approved_by && { id: approved_by_id, name: approved_by.name },
      can_approve: policy_allows && member.present? && Inclamo::ActionPermissions.allows?(member, action, facts.dig('request', 'params') || {}),
      result: record&.as_json
    }
  end
end
