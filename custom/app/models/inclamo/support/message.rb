# frozen_string_literal: true

class Inclamo::Support::Message < ApplicationRecord
  self.table_name = 'inclamo_support_messages'
  belongs_to :request, class_name: 'Inclamo::Support::Request'
end
