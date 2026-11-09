# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe Inclamo::Ai::ConnectionCode do
  include AiServiceStubs

  it 'reads the address and the token of a valid code' do
    code = described_class.read("  #{ai_code(service_url: 'https://ai.example.com/', token: 'tok-1')}\n")

    expect(code.service_url).to eq('https://ai.example.com')
    expect(code.token).to eq('tok-1')
    expect(code.connections_url).to eq('https://ai.example.com/connections')
  end

  it 'reads a code with base64 padding as well' do
    padded = "aic1.#{Base64.urlsafe_encode64({ service_url: 'https://ai.example.com', token: 't' }.to_json)}"

    expect(described_class.read(padded).token).to eq('t')
  end

  it 'refuses text that is not a code' do
    ['hello', '', nil, 'aic1.', 'aic1.not base64!', "aic1.#{Base64.urlsafe_encode64('not json')}", "aic1.#{Base64.urlsafe_encode64('[1,2]')}",
     "aic2.#{ai_code.delete_prefix('aic1.')}"].each do |text|
      expect { described_class.read(text) }.to raise_error(Inclamo::Ai::Error::InvalidCode), "accepted #{text.inspect}"
    end
  end

  it 'refuses an HTTP address' do
    expect { described_class.read(ai_code(service_url: 'http://ai.example.com')) }
      .to raise_error(Inclamo::Ai::Error::InvalidCode, /HTTPS/)
  end

  it 'accepts an HTTP address where Chatwoot may reach private networks (a test stack)' do
    allow(SafeFetch).to receive(:allow_private_network?).and_return(true)

    expect(described_class.read(ai_code(service_url: 'http://stand-in-agent:8090')).service_url).to eq('http://stand-in-agent:8090')
  end

  it 'refuses a code without the address or the token' do
    without_token = "aic1.#{Base64.urlsafe_encode64({ service_url: 'https://ai.example.com' }.to_json, padding: false)}"
    without_url = "aic1.#{Base64.urlsafe_encode64({ token: 'tok' }.to_json, padding: false)}"
    empty_token = ai_code(token: '')

    [without_token, without_url, empty_token].each do |text|
      expect { described_class.read(text) }.to raise_error(Inclamo::Ai::Error::InvalidCode)
    end
  end

  it 'refuses an address that is not a URL' do
    expect { described_class.read(ai_code(service_url: 'ai.example.com')) }.to raise_error(Inclamo::Ai::Error::InvalidCode)
    expect { described_class.read(ai_code(service_url: 'ftp://ai.example.com')) }.to raise_error(Inclamo::Ai::Error::InvalidCode)
  end
end
