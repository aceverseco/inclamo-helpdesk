# frozen_string_literal: true

class Inclamo::Support::CentralRequest < ApplicationRecord
  self.table_name = 'inclamo_support_central_requests'
  belongs_to :source, class_name: 'Inclamo::Support::Source'
  belongs_to :conversation
  has_many :receipts, class_name: 'Inclamo::Support::Receipt', dependent: :destroy
end
