# frozen_string_literal: true

class Inclamo::Support::Request < ApplicationRecord
  self.table_name = 'inclamo_support_requests'
  belongs_to :account
  belongs_to :author, class_name: 'User', optional: true
  has_many :submissions, class_name: 'Inclamo::Support::Submission', dependent: :destroy
  has_many :messages, class_name: 'Inclamo::Support::Message', dependent: :destroy
  has_many :reads, class_name: 'Inclamo::Support::Read', dependent: :destroy
  validates :category, inclusion: { in: %w[problem question suggestion] }
  validates :reference, format: { with: Inclamo::Support::UUID }

  def self.visible_to(member)
    scope = where(account_id: member.account_id)
    member.administrator? ? scope : scope.where(author_id: member.user_id)
  end

  def accessible_by?(member)
    member && member.account_id == account_id && (member.administrator? || member.user_id == author_id)
  end
end
