# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::Ai::DeliveryRecorder do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:website) { create(:inbox, account: account) }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:url) { 'https://ai.example.com/webhooks/conn-1' }
  let(:conversation) { create(:conversation, account: account, inbox: website) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: website) }
  let(:payload) { message.webhook_data.merge(event: 'message_created') }

  before do
    allow(GlobalConfig).to receive(:get_value).and_call_original
    allow(GlobalConfig).to receive(:get_value).with('WEBHOOK_TIMEOUT').and_return(5)
  end

  def deliver(type: :agent_bot_webhook, to: url, body: payload)
    Webhooks::Trigger.execute(to, body, type, secret: 'secret', delivery_id: SecureRandom.uuid)
  end

  it 'wraps a method that Chatwoot webhook sender still has' do
    method = Webhooks::Trigger.instance_method(:perform_request)

    expect(Webhooks::Trigger.ancestors.first).to eq(described_class)
    expect(method.owner).to eq(described_class)
    expect(method.super_method&.owner).to eq(Webhooks::Trigger)
  end

  it 'records a delivery the AI service took' do
    allow(SafeFetch).to receive(:fetch).and_yield(instance_double(SafeFetch::Result))

    deliver

    expect(record.reload).to have_attributes(state: 'connected', last_delivered_at: be_present, last_failed_at: nil)
  end

  it 'records a 503 as failing, with the status as its kind, and Chatwoot still opens the pending conversation' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable'))

    deliver

    expect(record.reload).to have_attributes(state: 'failing', last_error: 'http_503', last_failed_at: be_present)
    expect(conversation.reload.status).to eq('open')
  end

  it 'records a refused connection by its kind, never the message' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('Failed to open TCP connection to ai.example.com:443 (Connection refused)'))

    deliver

    expect(record.reload).to have_attributes(state: 'failing', last_error: 'connection_failed')
  end

  it 'records a timeout by its kind' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('Net::ReadTimeout with #<TCPSocket:(closed)>'))

    deliver

    expect(record.reload.last_error).to eq('timeout')
  end

  it 'records a 500 at every attempt Chatwoot makes, and still lets Chatwoot retry it' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

    expect { deliver }.to raise_error(Webhooks::Trigger::RetryableError)
    expect(record.reload).to have_attributes(state: 'failing', last_error: 'http_500')
  end

  it 'turns a failing connection connected again on the next delivery' do
    Inclamo::AiConnection.record_failure(record.id, 'http_503')
    allow(SafeFetch).to receive(:fetch).and_yield(instance_double(SafeFetch::Result))

    deliver

    expect(record.reload.state).to eq('connected')
  end

  it 'does not record a webhook of another kind, or to another address' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable'))

    deliver(type: :account_webhook)
    deliver(type: :api_inbox_webhook)
    deliver(to: 'https://elsewhere.example.com/hook')

    expect(record.reload).to have_attributes(state: 'connected', last_failed_at: nil)
  end
end
