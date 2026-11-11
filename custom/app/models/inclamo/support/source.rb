# frozen_string_literal: true

class Inclamo::Support::Source < ApplicationRecord
  self.table_name = 'inclamo_support_sources'
  has_many :requests, class_name: 'Inclamo::Support::CentralRequest', dependent: :destroy
end
