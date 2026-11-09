# frozen_string_literal: true

FactoryBot.define do
  factory :inclamo_ai_connection, class: 'Inclamo::AiConnection' do
    account
    service_url { 'https://ai.example.com' }
    connection_id { 'conn-1' }
    inbox_ids { [] }
    state { 'connected' }
    connected_at { Time.current }
  end
end
