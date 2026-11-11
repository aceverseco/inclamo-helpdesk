# frozen_string_literal: true

class Inclamo::Support::Delivery < ApplicationRecord
  self.table_name = 'inclamo_support_deliveries'
  belongs_to :recipient, class_name: 'Inclamo::Support::Recipient'
  belongs_to :central_request, class_name: 'Inclamo::Support::CentralRequest'
end
