# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/entry_requests')

# The record of a staff member's entry (docs/app-admin-entry.md §5): one row
# per request with the time, the store, the outcome and the user found, and
# one when an address is used; never the email, the address or its token.
RSpec.describe 'App admin entry: the record of attempts', type: :request do
  include_context 'with app admin entry'

  let!(:account) { store_account }
  let!(:alex) { member(account, 'alex@example.test', role: :administrator) }

  def last_event
    Inclamo::ProvisioningEvent.order(:id).last
  end

  def expect_recorded(outcome, user_id: nil, domain: ProvisioningRequests::STORE, request_id: :any)
    expect(last_event).to have_attributes(outcome: outcome, shop_domain: domain, user_id: user_id, account_id: nil)
    expect(last_event.request_id).to eq(request_id) unless request_id == :any
    expect(last_event.created_at).to be_within(10.seconds).of(Time.current)
  end

  it 'records each outcome with its time, the store, the request id and the user it found' do
    other = store_account('other-store.myshopify.com')
    pat = member(other, 'pat@example.test')
    ids = Array.new(9) { SecureRandom.uuid }

    expect { ask_entry(request_id: ids[0]) }.to change(Inclamo::ProvisioningEvent, :count).by(1)
    expect_recorded('entry_given', user_id: alex.id, request_id: ids[0])
    ask_entry(request_id: ids[1], staff: { email: 'nobody@example.test' })
    expect_recorded('entry_not_a_user', request_id: ids[1])
    ask_entry(request_id: ids[2], staff: { email: 'pat@example.test' })
    expect_recorded('entry_not_a_user', user_id: pat.id, request_id: ids[2])
    ask_entry('never-installed.myshopify.com', request_id: ids[3])
    expect_recorded('entry_no_account', domain: 'never-installed.myshopify.com', request_id: ids[3])
    ask_entry(request_id: ids[4], staff: { email_verified: false })
    expect_recorded('entry_refused', request_id: ids[4])
    ask_entry(request_id: ids[5], secret: 'another-secret-0123456789abcdef-0123456789abcdef')
    expect_recorded('entry_refused', request_id: ids[5])
    ask_entry(request_id: ids[0])
    expect_recorded('entry_refused', request_id: ids[0])
    alex.update!(otp_required_for_login: true)
    ask_entry(request_id: ids[6])
    expect_recorded('entry_two_factor', user_id: alex.id, request_id: ids[6])
    alex.update!(otp_required_for_login: false)
    remove_app
    ask_entry(request_id: ids[7])
    expect_recorded('entry_suspended', request_id: ids[7])

    expect(outcomes).to eq(%w[created entry_given entry_not_a_user entry_not_a_user entry_refused entry_refused entry_refused
                              entry_two_factor suspended entry_suspended])
  end

  it 'records a request over its limit as limited' do
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    with_modified_env INCLAMO_APP_PROVISIONING_ENTRY_PERSON_LIMIT: '1' do
      ask_entry(headers: { 'REMOTE_ADDR' => '203.0.113.9' })
      request_id = SecureRandom.uuid
      ask_entry(headers: { 'REMOTE_ADDR' => '203.0.113.9' }, request_id: request_id)
      expect(response).to have_http_status(:too_many_requests)
      expect_recorded('entry_limited', request_id: request_id)
    end
  ensure
    Rack::Attack.cache.store = store
    Rack::Attack.enabled = enabled
  end

  it 'records the use of an address with the user and the store' do
    ask_entry
    open_entry(entry_url)

    expect_recorded('entry_used', user_id: alex.id, request_id: nil)
  end

  it 'holds no email, name, address or token in any record, and neither does the request log' do
    url = nil
    text = logged do
      ask_entry
      url = entry_url
      open_entry(url)
      ask_entry(staff: { email: 'Nobody@Example.test' })
      ask_entry(staff: { email_verified: false })
    end
    token = url.split('/').last

    recorded = Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values }.join(' ')
    [/alex/i, /nobody/i, /example\.test/, alex.name, url, token, 'entry_url'].each do |personal|
      expect(recorded).not_to match(personal.is_a?(Regexp) ? personal : Regexp.new(Regexp.escape(personal)))
    end
    expect(text).to include('/inclamo/provisioning/stores/example-store.myshopify.com/entry')
    [url, token, 'entry_url', 'alex@example.test', 'Nobody@Example.test'].each do |secret_part|
      expect(text).not_to include(secret_part)
    end
  end

  it 'empties the user of a record when the user is deleted' do
    ask_entry
    event = last_event

    alex.destroy!

    expect(event.reload.user_id).to be_nil
    expect(event.outcome).to eq('entry_given')
  end
end
