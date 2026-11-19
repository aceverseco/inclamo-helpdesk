# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: the request body', type: :request do
  include_context 'with app provisioning'

  before { @before = [Account.count, User.count] }

  def expect_refused(code)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(code)
    expect(response.parsed_body['message']).to be_a(String).and be_present
    expect(response.parsed_body.keys).to contain_exactly('error', 'message')
    expect(Inclamo::ProvisionedAccount.count).to eq(0)
    expect([Account.count, User.count]).to eq(@before)
  end

  it 'refuses a store that is not a myshopify.com domain' do
    %w[shop.example.com example-store.myshopify.com.example.com -a.myshopify.com].each do |domain|
      provision(domain)
      expect_refused('shop_domain_invalid')
    end
  end

  it 'refuses a domain that differs from the address' do
    provision(body: provisioning_body('other-store.myshopify.com'))
    expect_refused('shop_domain_invalid')

    provision(body: provisioning_body.tap { |body| body[:shop].delete(:domain) })
    expect_refused('shop_domain_invalid')
  end

  it 'takes the domain whatever the case of its letters' do
    provision('Example-Store.myshopify.com', body: provisioning_body('EXAMPLE-STORE.MyShopify.com'))

    expect(response).to have_http_status(:created)
    expect(provisioned('example-store.myshopify.com')).to be_present
  end

  it 'refuses a missing store name' do
    [{ name: nil }, { name: '' }, { name: '   ' }, { name: 7 }].each do |shop|
      provision(shop: shop)
      expect_refused('shop_name_missing')
    end
  end

  it 'refuses a missing email' do
    [{ email: nil }, { email: '' }, { email: 'not an email' }, { email: ['alex@example.test'] }].each do |admin|
      provision(admin: admin)
      expect_refused('admin_email_missing')
    end
  end

  it 'accepts a missing name: the email stands in for it' do
    [{ name: nil }, { name: ' ' }, { name: 7 }].each_with_index do |admin, index|
      provision("store-#{index}.myshopify.com", admin: admin.merge(email: "person-#{index}@example.test"))
      expect(response).to have_http_status(:created)
      expect(User.from_email("person-#{index}@example.test").name).to eq("person-#{index}@example.test")
    end
  end

  it 'refuses an address for key requests that is not an absolute HTTPS address' do
    ['', 'http://app.example.test/store-access', '/store-access', 'app.example.test', 'https://', 'https://exa mple.test', 7, {},
     "https://app.example.test/#{'a' * 2048}"].each do |url|
      provision(store_access_url: url)
      expect_refused('store_access_url_invalid')
    end
  end

  it 'refuses an email that Shopify did not verify' do
    body = provisioning_body
    body[:admin].delete(:email_verified)
    provision(body: body)
    expect_refused('admin_email_unverified')

    [false, nil, 'true', 1].each do |value|
      provision(admin: { email_verified: value })
      expect_refused('admin_email_unverified')
    end
    expect(User.from_email('alex@example.test')).to be_nil
  end

  it 'refuses a contract it does not speak' do
    [2, '1', nil].each do |version|
      provision(body: provisioning_body(contract: version))
      expect_refused('contract_unsupported')
    end
    provision(body: provisioning_body.except(:contract))
    expect_refused('contract_unsupported')
  end

  it 'refuses a body that is not a JSON object, with one of the contract codes' do
    ['', '[]', '"text"'].each do |raw|
      provision(body: raw)
      expect_refused('contract_unsupported')
    end
  end

  it 'refuses a signed body that is broken JSON the same way' do
    provision(body: '{"contract":1,"shop":')

    expect_refused('contract_unsupported')
  end

  it 'records each refusal without the person' do
    provision(admin: { email_verified: false })

    event = Inclamo::ProvisioningEvent.last
    expect(event).to have_attributes(outcome: 'refused', shop_domain: ProvisioningRequests::STORE)
    expect(event.attributes.values.join(' ')).not_to match(/alex|Alex/)
  end
end
