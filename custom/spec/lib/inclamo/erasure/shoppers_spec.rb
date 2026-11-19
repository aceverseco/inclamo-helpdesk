# frozen_string_literal: true

require 'rails_helper'

# Finding one shopper in a store's account (docs/app-store-erasure.md §4.2):
# the email without regard to letter case, the phone by its digits, inside
# that account only, and never the tickets' own contact.
RSpec.describe Inclamo::Erasure::Shoppers do
  let(:account) { create(:account) }
  let!(:by_email) { create(:contact, account: account, email: 'Pat@Example.com', phone_number: nil) }
  let!(:by_phone) { create(:contact, account: account, email: 'someone@example.com', phone_number: '+15556251199') }
  let!(:other) { create(:contact, account: account, email: 'kim@example.com', phone_number: '+15550000002') }

  def found(email: nil, phone: nil, within: account)
    described_class.matching(within, email: email, phone: phone).pluck(:id)
  end

  it 'finds by the email without regard to letter case or surrounding blanks' do
    expect(found(email: ' PAT@example.COM ')).to eq([by_email.id])
  end

  it 'finds by the phone\'s digits, written with spaces, a plus, dashes and brackets' do
    ['+1 555 625 1199', '1 (555) 625-1199', '15556251199', '+1.555.625.1199'].each do |phone|
      expect(found(phone: phone)).to eq([by_phone.id])
    end
    expect(found(phone: '555 625 1199')).to eq([])
  end

  it 'finds by either, and each contact once' do
    expect(found(email: 'pat@example.com', phone: '+15556251199')).to contain_exactly(by_email.id, by_phone.id)
    by_phone.update!(email: 'pat2@example.com')
    expect(found(email: 'pat2@example.com', phone: '+15556251199')).to eq([by_phone.id])
  end

  it 'finds nothing in another account, even with the same email and phone' do
    elsewhere = create(:account)
    theirs = create(:contact, account: elsewhere, email: 'pat@example.com', phone_number: '+15556251199')

    expect(found(email: 'pat@example.com', phone: '+15556251199')).not_to include(theirs.id)
    expect(found(email: 'pat@example.com', phone: '+15556251199', within: elsewhere)).to eq([theirs.id])
  end

  it 'finds nothing without an email or a phone with digits, and nothing in no account' do
    expect(found).to eq([])
    expect(found(email: ' ', phone: 'none')).to eq([])
    expect(described_class.matching(nil, email: 'pat@example.com', phone: nil)).to be_empty
  end

  it 'never takes the tickets\' own contact, whatever is written on it' do
    place = Inclamo::Erasure::Ticket.place!(account)
    place.contact.update!(email: 'shared@example.com')

    expect(found(email: 'shared@example.com')).to eq([])
  end

  it 'digests the compared forms with the installation\'s key, the same way each time' do
    key = Rails.application.key_generator.generate_key('inclamo erasure shopper digest', 32)

    expect(described_class.digest(described_class.email(' Pat@Example.com'))).to eq(OpenSSL::HMAC.hexdigest('SHA256', key, 'pat@example.com'))
    expect(described_class.digest(described_class.digits('+1 555 625 1199'))).to eq(OpenSSL::HMAC.hexdigest('SHA256', key, '15556251199'))
    expect(described_class.digest(nil)).to be_nil
  end
end
