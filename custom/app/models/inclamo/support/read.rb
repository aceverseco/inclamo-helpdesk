# frozen_string_literal: true

class Inclamo::Support::Read < ApplicationRecord
  self.table_name = 'inclamo_support_reads'
  belongs_to :request, class_name: 'Inclamo::Support::Request'
  belongs_to :account_user
end
