# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

# Suspension is Chatwoot's own account status; this pins that an email arriving
# for an inbox of a suspended provisioned account is not taken in.
RSpec.describe ReplyMailbox do
  include ActionMailbox::TestHelper

  let(:provision) do
    payload = instance_double(Inclamo::Provisioning::Payload, shop_domain: 'example-store.myshopify.com', shop_name: 'Example Store',
                                                             locale: nil, timezone: nil, admin_email: 'alex@example.test',
                                                             admin_name: 'Alex Example', store_access_url: nil)
    Inclamo::Provisioning::Provision.new(payload)
  end
  let(:account) { provision.call.account }
  let!(:channel) { create(:channel_email, account: account, email: 'care@example.com') }
  let(:mail) { create_inbound_email_from_fixture('support.eml') }

  it 'accepts an incoming email while the account is active' do
    expect { described_class.receive(mail) }.to change { channel.inbox.conversations.count }.by(1)
  end

  it 'does not accept an incoming email once the app was removed, and accepts again after restoration' do
    expect(Inclamo::Provisioning::Removal.new('example-store.myshopify.com').call).to eq('suspended')

    expect { described_class.receive(mail) }.to not_change(Conversation, :count).and not_change(Message, :count)

    expect(provision.call.outcome).to eq('restored')
    later = Rails.root.join('spec/fixtures/files/support.eml').read.sub(/^Message-ID:.*$/i, 'Message-ID: <after-restoration@example.com>')
    expect { described_class.receive(create_inbound_email_from_source(later)) }.to change { channel.inbox.conversations.count }.by(1)
  end
end
