# frozen_string_literal: true

class Inclamo::Support::Receipt < ApplicationRecord
  self.table_name = 'inclamo_support_receipts'
  belongs_to :source, class_name: 'Inclamo::Support::Source'
  belongs_to :central_request, class_name: 'Inclamo::Support::CentralRequest'
  belongs_to :message, class_name: '::Message'
end
