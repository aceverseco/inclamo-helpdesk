# frozen_string_literal: true

class Inclamo::Support::Recipient < ApplicationRecord
  self.table_name = 'inclamo_support_recipients'
  belongs_to :source, class_name: 'Inclamo::Support::Source'
end
