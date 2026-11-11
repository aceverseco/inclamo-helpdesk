# frozen_string_literal: true

class Inclamo::Support::Event < ApplicationRecord
  self.table_name = 'inclamo_support_events'
  belongs_to :source, class_name: 'Inclamo::Support::Source'
  belongs_to :central_request, class_name: 'Inclamo::Support::CentralRequest'
end
