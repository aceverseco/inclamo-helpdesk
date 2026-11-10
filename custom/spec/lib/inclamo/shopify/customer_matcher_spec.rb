# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::CustomerMatcher do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:reader) { Inclamo::Shopify::OrderReader.new(record) }
  let(:maya) { shopify_fixture('customers_search_one').dig('customers', 'nodes', 0) }

  before { Inclamo::Shopify::OrderReader.forget!(record.account_id) }

  def match(contact, limited: false)
    described_class.new(reader, contact, limited: limited).call
  end

  def contact(**attributes)
    create(:contact, account: record.account, **attributes)
  end

  it 'uses the one customer with the contact\'s email' do
    stub_shopify_fixture(:customers_search, 'customers_search_one')

    result = match(contact(email: 'maya.example.t001@example.com'))

    expect(result.to_h).to include(state: 'matched', customer_id: maya['id'])
  end

  it 'falls back to the phone when the email finds nobody' do
    by_email = stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body).dig('variables', 'query').to_s.start_with?('email:') }
                                                       .to_return(status: 200, body: { data: shopify_fixture('customers_search_none') }.to_json, headers: ShopifyStubs::JSON_HEADERS)
    by_phone = stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body).dig('variables', 'query').to_s.start_with?('phone:') }
                                                       .to_return(status: 200, body: { data: shopify_fixture('customers_search_phone') }.to_json, headers: ShopifyStubs::JSON_HEADERS)

    result = match(contact(email: 'someone.else@example.com', phone_number: '+15005551011'))

    expect(result.state).to eq('matched')
    expect(by_email).to have_been_requested.once
    expect(by_phone).to have_been_requested.once
  end

  it 'chooses nobody when two customers share the phone, and lists both' do
    twin = maya.merge('id' => 'gid://shopify/Customer/2', 'displayName' => 'Mia Example')
    stub_shopify(:customers_search, data: { customers: { nodes: [maya, twin] } })

    result = match(contact(email: nil, phone_number: '+15005551011'))

    expect(result.state).to eq('ambiguous')
    expect(result.customer_id).to be_nil
    expect(result.candidates.pluck(:name)).to eq(['Maya Example', 'Mia Example'])
  end

  it 'reports nobody when neither finds a customer' do
    stub_shopify_fixture(:customers_search, 'customers_search_none')

    expect(match(contact(email: 'nobody.t001@example.com')).state).to eq('none')
  end

  it 'asks the store nothing for a contact without email and phone' do
    expect(match(contact(email: nil, phone_number: nil)).state).to eq('no_identifier')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'uses the customer an agent chose earlier, without searching' do
    chosen = contact(email: 'someone.else@example.com')
    described_class.remember!(chosen, maya['id'])

    expect(match(chosen.reload).to_h).to include(state: 'matched', customer_id: maya['id'])
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end

  it 'forgets the choice when asked' do
    chosen = contact(email: nil, phone_number: nil)
    described_class.remember!(chosen, maya['id'])
    described_class.remember!(chosen, nil)

    expect(chosen.reload.custom_attributes).not_to include(described_class::REMEMBERED)
  end

  it 'matches nobody when the store hides customer data' do
    expect(match(contact(email: 'maya.example.t001@example.com'), limited: true).state).to eq('limited')
    expect(WebMock).not_to have_requested(:any, /myshopify/)
  end
end
