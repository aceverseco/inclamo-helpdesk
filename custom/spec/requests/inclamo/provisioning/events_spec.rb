# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: the record of attempts', type: :request do
  include_context 'with app provisioning'

  def last_event
    Inclamo::ProvisioningEvent.order(:id).last
  end

  def expect_recorded(outcome, request_id, domain = ProvisioningRequests::STORE)
    expect(last_event).to have_attributes(outcome: outcome, shop_domain: domain, request_id: request_id)
    expect(last_event.created_at).to be_within(10.seconds).of(Time.current)
  end

  it 'records each outcome with its time, the store and the request id' do
    ids = Array.new(8) { SecureRandom.uuid }

    expect { provision(request_id: ids[0]) }.to change(Inclamo::ProvisioningEvent, :count).by(1)
    expect_recorded('created', ids[0])
    provision(request_id: ids[1])
    expect_recorded('existed', ids[1])
    remove_app(request_id: ids[2])
    expect_recorded('suspended', ids[2])
    remove_app(request_id: ids[3])
    expect_recorded('suspended', ids[3])
    provision(request_id: ids[4])
    expect_recorded('restored', ids[4])
    remove_app('unknown-store.myshopify.com', request_id: ids[5])
    expect_recorded('none', ids[5], 'unknown-store.myshopify.com')
    provision(request_id: ids[6], secret: 'another-secret-0123456789abcdef-0123456789abcdef')
    expect_recorded('refused', ids[6])
    provision(request_id: ids[7], admin: { email_verified: false })
    expect_recorded('refused', ids[7])

    expect(Inclamo::ProvisioningEvent.order(:id).pluck(:outcome))
      .to eq(%w[created existed suspended suspended restored none refused refused])
  end

  it 'records a refused removal and a refused question too' do
    remove_app(timestamp: 10.minutes.ago.to_i)
    expect(last_event).to have_attributes(outcome: 'refused', shop_domain: ProvisioningRequests::STORE)
    expect { get provisioning_path('other-store.myshopify.com') }.to change(Inclamo::ProvisioningEvent, :count).by(1)
    expect(last_event).to have_attributes(outcome: 'refused', shop_domain: 'other-store.myshopify.com', request_id: nil)
  end

  it 'records a repeated request id with the outcome it was given' do
    request_id = SecureRandom.uuid
    body = provisioning_body
    provision(body: body, request_id: request_id)
    provision(body: body, request_id: request_id)

    expect(Inclamo::ProvisioningEvent.where(request_id: request_id).pluck(:outcome)).to eq(%w[created created])
  end

  it 'holds no email, name, signature, secret or link in any record' do
    provision
    link = response.parsed_body.fetch('password_setup_url')
    provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
    remove_app
    provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
    provision(secret: 'another-secret-0123456789abcdef-0123456789abcdef')
    signature = request.headers['X-Inclamo-Signature']
    provision(admin: { email: 'not an email' })

    recorded = Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values }.join(' ')
    expect(Inclamo::ProvisioningEvent.count).to eq(6)
    expect(signature).to match(/\Asha256=\h{64}\z/)
    [/alex/i, /sam/i, /example\.test/, /Example Store/, signature, signature.delete_prefix('sha256='), ProvisioningRequests::SECRET,
     link, 'not an email'].each do |personal|
      expect(recorded).not_to match(personal.is_a?(Regexp) ? personal : Regexp.new(Regexp.escape(personal)))
    end
  end
end
