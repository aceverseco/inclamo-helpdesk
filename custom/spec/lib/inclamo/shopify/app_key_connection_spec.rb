# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/store_key_stubs')

# A store connection through the store app (`app_key`): renewed with keys from
# the app, never called broken because the app is silent, broken with a
# reason when the app says why.
RSpec.describe Inclamo::Shopify::StoreConnection do
  include_context 'with the store app for keys'

  let(:account) { provisioned_account }
  let(:record) { app_key_connection(account) }
  let(:store) { described_class.new(record) }

  def shop_answer
    { status: 200, body: { data: shop_info_data }.to_json, headers: ShopifyStubs::JSON_HEADERS }
  end

  def store_accepts(token)
    stub_request(:post, shopify_graphql_url).with(headers: { 'X-Shopify-Access-Token' => token }).to_return(shop_answer)
  end

  def store_refuses(token)
    stub_request(:post, shopify_graphql_url).with(headers: { 'X-Shopify-Access-Token' => token }).to_return(status: 401, body: '{}')
  end

  describe 'renewal' do
    it 'uses the key while it is fresh and asks the app for nothing' do
      key = stub_store_key
      store_accepts(StoreKeyStubs::KEY)

      store.query(:shop_info)

      expect(key).not_to have_been_requested
    end

    it 'asks the app for a new key five minutes before the end, not after it' do
      record.update!(token_expires_at: 4.minutes.from_now)
      key = stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY, scopes: %w[read_customers read_orders write_orders]))
      fresh = store_accepts(StoreKeyStubs::NEW_KEY)

      store.query(:shop_info)

      expect(key).to have_been_requested.once
      expect(fresh).to have_been_requested.once
      expect(record.reload).to have_attributes(access_token: StoreKeyStubs::NEW_KEY, scopes: %w[read_customers read_orders write_orders])
      expect(record.token_expires_at).to be > 55.minutes.from_now
      expect(record.renewed_at).to be_within(1.minute).of(Time.current)
    end

    it 'does not ask at six minutes before the end' do
      record.update!(token_expires_at: 6.minutes.from_now)
      key = stub_store_key
      store_accepts(StoreKeyStubs::KEY)

      store.query(:shop_info)

      expect(key).not_to have_been_requested
    end

    it 'retries a request the store refused once, with a new key, and stays working' do
      stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY))
      store_refuses(StoreKeyStubs::KEY)
      store_accepts(StoreKeyStubs::NEW_KEY)

      expect(store.query(:shop_info)).to include('shop')
      expect(record.reload).to be_working
      expect(record.access_token).to eq(StoreKeyStubs::NEW_KEY)
    end

    it 'asks for that key also within the pause after another attempt' do
      described_class.new(record).send(:pause!)
      key = stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY))
      store_refuses(StoreKeyStubs::KEY)
      store_accepts(StoreKeyStubs::NEW_KEY)

      expect(store.query(:shop_info)).to include('shop')
      expect(key).to have_been_requested.once
    end

    it 'marks the connection broken when the store refuses the new key too' do
      stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY))
      store_refuses(StoreKeyStubs::KEY)
      second = store_refuses(StoreKeyStubs::NEW_KEY)

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::Unauthorized)
      expect(record.reload).to be_broken
      expect(second).to have_been_requested.once
      expect { described_class.new(record).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::ConnectionBroken)
    end
  end

  describe 'an app that does not answer' do
    it 'costs nothing while the key still works' do
      record.update!(token_expires_at: 3.minutes.from_now)
      stub_request(:post, store_key_url).to_timeout
      current = store_accepts(StoreKeyStubs::KEY)

      expect(store.query(:shop_info)).to include('shop')
      expect(current).to have_been_requested.once
      expect(record.reload).to be_working
    end

    it 'gives no store data past the key, and leaves the connection working' do
      record.update!(token_expires_at: 3.minutes.from_now)
      stub_request(:post, store_key_url).to_timeout
      graphql = store_accepts(StoreKeyStubs::KEY)

      travel_to(150.seconds.from_now) do
        expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      end
      expect(graphql).not_to have_been_requested
      expect(record.reload).to be_working
      expect(record.broken_reason).to be_nil
    end

    def pause_left
      Redis::Alfred.ttl("inclamo:shopify:#{record.id}:app_key_pause")
    end

    it 'asks the app at most once in the 30 s pause, then again after it, and recovers by itself' do
      record.update!(token_expires_at: 30.seconds.ago)
      key = stub_store_key({ status: 503, body: { error: 'store_unavailable' } }, key_answer(token: StoreKeyStubs::NEW_KEY))
      store_accepts(StoreKeyStubs::NEW_KEY)

      3.times { expect { described_class.new(record.reload).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) }
      expect(key).to have_been_requested.once
      expect(pause_left).to be_between(25, 30)

      # The pause is a Redis expiry: it passes here as it would after 30 s.
      clear_app_key_pauses
      expect(described_class.new(record.reload).query(:shop_info)).to include('shop')
      expect(key).to have_been_requested.twice
      expect(record.reload.access_token).to eq(StoreKeyStubs::NEW_KEY)
    end

    it 'waits as long as the app asked, when longer than the pause' do
      record.update!(token_expires_at: 30.seconds.ago)
      key = stub_store_key(key_refusal(503, 'store_unavailable', headers: { 'Retry-After' => '120' }), key_answer)

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(pause_left).to be_between(115, 120)
      expect { described_class.new(record.reload).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(key).to have_been_requested.once
    end

    it 'takes the pause from the operator setting' do
      record.update!(token_expires_at: 30.seconds.ago)
      stub_request(:post, store_key_url).to_timeout

      with_modified_env(INCLAMO_APP_KEY_PAUSE: '90') { expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) }
      expect(pause_left).to be_between(85, 90)
    end

    it 'counts every answer that is no key as no answer: 503, 401, 422, 429, a server error' do
      [key_refusal(503, 'store_unavailable'), key_refusal(401, 'unauthorized'), key_refusal(422, 'contract_unsupported'),
       key_refusal(429, 'rate_limited'), { status: 500, body: '' }].each do |answer|
        clear_app_key_pauses
        record.update!(token_expires_at: 30.seconds.ago, status: 'working')
        stub_store_key(answer)

        expect { described_class.new(record).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
        expect(record.reload).to be_working
      end
    end

    it 'does not keep a key the store refused when the app gives no other' do
      stub_request(:post, store_key_url).to_timeout
      store_refuses(StoreKeyStubs::KEY)

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(record.reload).to be_working
      expect(record.access_token).to be_nil
    end
  end

  describe "the app's refusals" do
    before { record.update!(token_expires_at: 30.seconds.ago) }

    it 'mark the connection broken as removed when the store does not have the app' do
      stub_store_key(key_refusal(404, 'store_not_installed'))

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::AppKeyRefused)
      expect(record.reload).to have_attributes(status: 'broken', broken_reason: 'app_removed')
    end

    it 'mark it broken as an account mismatch when the app does not know the account for the store' do
      stub_store_key(key_refusal(403, 'account_mismatch'))

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::ConnectionBroken)
      expect(record.reload).to have_attributes(status: 'broken', broken_reason: 'account_mismatch')
    end

    it 'mark it broken when the new key cannot read the store' do
      stub_store_key(key_answer(scopes: %w[read_customers write_orders]))

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::ConnectionBroken)
      expect(record.reload).to have_attributes(status: 'broken', broken_reason: 'missing_read_scope')
    end

    it 'take a key to another store as no answer' do
      stub_store_key(key_answer(domain: 'another-store.myshopify.com'))

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(record.reload).to be_working
    end
  end

  describe 'a scope the store refuses to the key' do
    it 'asks the app for a key with the scopes it holds now' do
      stub_shopify(:shop_info, errors: [{ message: 'Access denied for orderCancel field.', extensions: { code: 'ACCESS_DENIED' } }])
      key = stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY, scopes: %w[read_customers read_orders]))

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::QueryError)
      expect(key).to have_been_requested.once
      expect(record.reload.scopes).to eq(%w[read_customers read_orders])
      expect(record.unavailable_reason('cancel')).to eq('missing_scope')

      expect { described_class.new(record).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::QueryError)
      expect(key).to have_been_requested.once
    end
  end

  describe '#recheck!' do
    before do
      stub_shopify(:shop_identity, data: { shop: { name: 'Example Store', myshopifyDomain: StoreKeyStubs::STORE, currencyCode: 'EUR' } })
      stub_shopify(:customer_data_probe, data: { orders: { nodes: [] }, customers: { nodes: [] } })
    end

    it 'takes a new key with its scopes, and repairs a broken connection' do
      record.update!(status: 'broken', broken_reason: 'app_removed', scopes: %w[read_customers read_orders])
      stub_store_key(key_answer(token: StoreKeyStubs::NEW_KEY, scopes: %w[read_customers read_orders write_orders write_order_edits]))

      store.recheck!

      expect(record.reload).to have_attributes(status: 'working', broken_reason: nil, access_token: StoreKeyStubs::NEW_KEY,
                                               scopes: %w[read_customers read_orders write_order_edits write_orders])
      expect(record.unavailable_reason('edit_items')).to be_nil
      expect(record.last_checked_at).to be_within(1.minute).of(Time.current)
    end

    it 'reads no scopes from the store' do
      stub_store_key
      store.recheck!

      expect(WebMock).not_to have_requested(:post, shopify_graphql_url).with { |request| request.body.include?('currentAppInstallation') }
    end

    it 'is refused with the reason when the app still says the store does not have it' do
      stub_store_key(key_refusal(404, 'store_not_installed'))

      expect { store.recheck! }.to raise_error(Inclamo::Shopify::Error::AppKeyRefused)
      expect(record.reload).to have_attributes(status: 'broken', broken_reason: 'app_removed')
    end
  end

  describe 'without what it needs' do
    it 'asks nothing once the account is suspended, and gives no store data' do
      record.update!(token_expires_at: 30.seconds.ago)
      Inclamo::ProvisionedAccount.find_by(account_id: account.id).update!(state: 'suspended')
      key = stub_store_key

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(key).not_to have_been_requested
    end

    {
      'the shared secret' => { INCLAMO_APP_PROVISIONING_SECRET: nil },
      "the app's address" => { INCLAMO_APP_URL: nil },
      "an HTTPS address of the app" => { INCLAMO_APP_URL: 'http://app.example.test/helpdesk' }
    }.each do |missing, env|
      it "sends no request without #{missing}" do
        record.update!(token_expires_at: 30.seconds.ago)
        key = stub_request(:post, /store-key/)

        with_modified_env(**env) { expect { described_class.new(record).query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) }
        expect(key).not_to have_been_requested
      end
    end

    it 'sends no request without encryption keys' do
      record.update!(token_expires_at: 30.seconds.ago)
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      key = stub_request(:post, /store-key/)

      expect { store.query(:shop_info) }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(key).not_to have_been_requested
    end
  end
end
