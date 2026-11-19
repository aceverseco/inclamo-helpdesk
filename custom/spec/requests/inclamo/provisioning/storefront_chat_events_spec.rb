# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App storefront chat: the record of attempts', type: :request do
  include_context 'with app provisioning'

  def last_event
    Inclamo::ProvisioningEvent.order(:id).last
  end

  def expect_recorded(outcome, request_id, domain = ProvisioningRequests::STORE)
    expect(last_event).to have_attributes(outcome: outcome, shop_domain: domain, request_id: request_id)
    expect(last_event.created_at).to be_within(10.seconds).of(Time.current)
  end

  it 'records the three outcomes with the time, the store and the request id' do
    linked_account
    ids = Array.new(7) { SecureRandom.uuid }

    expect { ask_for_chat(request_id: ids[0]) }.to change(Inclamo::ProvisioningEvent, :count).by(1)
    expect_recorded('chat_created', ids[0])
    ask_for_chat(request_id: ids[1])
    expect_recorded('chat_existed', ids[1])
    ask_for_chat(request_id: ids[2], with: { storefront_url: 'http://not-https.example' })
    expect_recorded('chat_refused', ids[2])
    ask_for_chat(request_id: ids[3], body: { contract: 2 })
    expect_recorded('chat_refused', ids[3])
    ask_for_chat('unknown-store.myshopify.com', request_id: ids[4])
    expect_recorded('chat_refused', ids[4], 'unknown-store.myshopify.com')
    remove_app
    ask_for_chat(request_id: ids[5])
    expect_recorded('chat_refused', ids[5])
    # Who is asking is the channel's own check, and keeps the channel's outcome.
    ask_for_chat(request_id: ids[6], secret: 'another-secret-0123456789abcdef-0123456789abcdef')
    expect_recorded('refused', ids[6])

    expect(Inclamo::ProvisioningEvent.order(:id).pluck(:outcome))
      .to eq(%w[chat_created chat_existed chat_refused chat_refused chat_refused suspended chat_refused refused])
  end

  it 'records the inbox made with the account under the account\'s outcome alone' do
    provision

    expect(Inclamo::ProvisioningEvent.pluck(:outcome)).to eq(['created'])
  end

  it 'records a repeated request id with the outcome it was given' do
    linked_account
    request_id = SecureRandom.uuid
    2.times { ask_for_chat(request_id: request_id) }

    expect(Inclamo::ProvisioningEvent.where(request_id: request_id).pluck(:outcome)).to eq(%w[chat_created chat_created])
  end

  it 'does not record the status call, as the channel does not record its own' do
    provision

    expect do
      ask_chat_status
      ask_chat_status('unknown-store.myshopify.com')
    end.to not_change(Inclamo::ProvisioningEvent, :count)
  end

  it 'holds no token, address, signature or secret in any record' do
    linked_account
    ask_for_chat(with: { storefront_url: 'https://maple-and-oak.example' })
    channel = storefront_inbox.channel
    ask_for_chat
    ask_chat_status
    ask_for_chat(with: { storefront_url: 'http://not-https.example' })
    ask_for_chat(secret: 'another-secret-0123456789abcdef-0123456789abcdef')
    signature = request.headers['X-Inclamo-Signature']

    expect(Inclamo::ProvisioningEvent.pluck(:outcome)).to eq(%w[chat_created chat_existed chat_refused refused])
    expect(Inclamo::ProvisioningEvent.column_names).to contain_exactly('id', 'shop_domain', 'outcome', 'request_id', 'account_id', 'created_at')
    recorded = Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values }.join(' ')
    [channel.website_token, channel.hmac_token, 'maple-and-oak', 'not-https', signature, signature.delete_prefix('sha256='),
     ProvisioningRequests::SECRET].each do |hidden|
      expect(recorded).not_to include(hidden)
    end
  end
end
