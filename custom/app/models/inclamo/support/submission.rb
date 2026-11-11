# frozen_string_literal: true

class Inclamo::Support::Submission < ApplicationRecord
  self.table_name = 'inclamo_support_submissions'
  belongs_to :request, class_name: 'Inclamo::Support::Request'
  belongs_to :actor, class_name: 'User', optional: true
  has_many :uploads, class_name: 'Inclamo::Support::Upload', dependent: :destroy
  validates :body, presence: true, length: { maximum: Inclamo::Support::MAX_BODY }
  validates :uuid, format: { with: Inclamo::Support::UUID }
end
