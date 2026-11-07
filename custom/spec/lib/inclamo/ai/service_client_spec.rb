# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::Ai::ServiceClient do
  include AiServiceStubs

  let(:client) { described_class.new }
  let(:code) { Inclamo::Ai::ConnectionCode.read(ai_code) }
  let(:body) { { contract: 1, account: { id: 1, name: 'Shop' } } }

  before { resolve_ai_service_publicly }

  describe '#register' do
    it 'sends the body with the code token and reads a 201' do
      stub = stub_ai_registration
      registration = client.register(code, body)

      expect(registration).to have_attributes(connection_id: 'conn-1', webhook_url: 'https://ai.example.com/webhooks/conn-1')
      expect(stub.with(headers: { 'Authorization' => 'Bearer one-time-token-for-specs', 'Content-Type' => 'application/json' },
                       body: body.to_json)).to have_been_requested
    end

    it 'turns a 4xx with a message into a refusal with the AI service message' do
      stub_ai_registration(status: 410, body: { error: 'expired', message: 'This connection code has expired.' })

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::Refused, 'This connection code has expired.') { |error|
        expect(error.service_error).to eq('expired')
      }
    end

    it 'refuses in its own words when a 4xx has no message' do
      stub_ai_registration(status: 403, body: '<html>Forbidden</html>')

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::Refused, I18n.t('inclamo.ai_connection.errors.refused_without_message'))
    end

    it 'takes a 5xx as no answer' do
      stub_ai_registration(status: 503, body: { error: 'down' })

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::NotAnswered)
    end

    it 'takes a timeout as no answer' do
      stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_timeout

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::NotAnswered)
    end

    it 'takes a refused connection as no answer' do
      stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_raise(Errno::ECONNREFUSED)

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::NotAnswered)
    end

    it 'takes a 201 without a webhook address, or with an HTTP one, as no answer, keeping the id to remove it' do
      stub_ai_registration(body: { connection_id: 'conn-9', webhook_url: 'http://ai.example.com/hook' })

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::NotAnswered) { |error| expect(error.connection_id).to eq('conn-9') }
    end

    it 'does not follow a redirect' do
      stub_request(:post, "#{AiServiceStubs::AI_SERVICE_URL}/connections").to_return(status: 307, headers: { 'Location' => 'https://elsewhere.example.com/connections' })

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::NotAnswered)
      expect(a_request(:post, 'https://elsewhere.example.com/connections')).not_to have_been_made
    end

    it 'refuses a private address unless private networks are allowed' do
      allow(described_class).to receive(:resolver).and_return(->(_host) { [IPAddr.new('10.0.0.7')] })
      stub = stub_ai_registration

      expect { client.register(code, body) }.to raise_error(Inclamo::Ai::Error::NotAnswered)
      expect(stub).not_to have_been_requested
    end
  end

  describe '#remove' do
    it 'deletes the connection with the given token' do
      stub = stub_ai_removal

      expect(client.remove(service_url: AiServiceStubs::AI_SERVICE_URL, connection_id: 'conn-1', token: 'bot-token')).to be(true)
      expect(stub.with(headers: { 'Authorization' => 'Bearer bot-token' })).to have_been_requested
    end

    it 'raises when the AI service does not take it' do
      stub_ai_removal(status: 500)

      expect { client.remove(service_url: AiServiceStubs::AI_SERVICE_URL, connection_id: 'conn-1', token: 'bot-token') }.to raise_error(Inclamo::Ai::Error::NotAnswered)
    end
  end
end
