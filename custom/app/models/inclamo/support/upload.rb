# frozen_string_literal: true

class Inclamo::Support::Upload < ApplicationRecord
  self.table_name = 'inclamo_support_uploads'
  belongs_to :source, class_name: 'Inclamo::Support::Source', optional: true
  belongs_to :account_user, optional: true
  belongs_to :submission, class_name: 'Inclamo::Support::Submission', optional: true
  belongs_to :receipt, class_name: 'Inclamo::Support::Receipt', optional: true
  has_one_attached :file
end
