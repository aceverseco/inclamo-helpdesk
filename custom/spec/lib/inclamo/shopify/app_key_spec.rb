# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/store_key_stubs')

# The request for a store key (docs/app-store-access.md §1–§3): where it goes,
# how it is signed, what is taken from the answer, and what is recorded.
RSpec.describe Inclamo::Shopify::AppKey do
  include_context 'with the store app for keys'

  let(:account) { provisioned_account }
  let(:row) { Inclamo::ProvisionedAccount.find_by(account_id: account.id) }

  def ask(**)
    described_class.call(row: row, account_id: account.id, **)
  end

  describe 'the request' do
    it 'is a POST to the store under the app address, signed over the path as sent, the prefix included' do
      stub = stub_store_key

      ask

      expect(stub).to have_been_requested.once
      expect(a_request(:post, store_key_url).with do |request|
        body = JSON.parse(request.body)
        path = URI.parse(request.uri.to_s).path
        signed = Inclamo::Provisioning::Signature.sign(StoreKeyStubs::SECRET, timestamp: request.headers['X-Inclamo-Timestamp'], method: 'POST',
                                                                              request_id: request.headers['X-Inclamo-Request-Id'], path: path, body: request.body)
        path == "/helpdesk/stores/#{StoreKeyStubs::STORE}/store-key" && body == { 'contract' => 1, 'account_id' => account.id, 'scopes' => described_class.scopes } &&
          request.headers['X-Inclamo-Signature'] == signed && request.headers['X-Inclamo-Request-Id'].match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      end).to have_been_made.once
    end

    it 'reproduces the worked example of the contract' do
      with_modified_env INCLAMO_APP_PROVISIONING_SECRET: 'test-secret-not-for-production-0123456789abcdef', INCLAMO_APP_URL: 'https://app.example.com/helpdesk' do
        example_row = Inclamo::ProvisionedAccount.new(shop_domain: 'example-store.myshopify.com', state: 'active')
        body = '{"contract":1,"account_id":42,"scopes":["read_customers","read_orders","read_products","write_orders","write_draft_orders",' \
               '"write_customers","write_order_edits","write_discounts","read_locations","read_merchant_managed_fulfillment_orders"]}'
        stub = stub_request(:post, 'https://app.example.com/helpdesk/stores/example-store.myshopify.com/store-key')
               .with(body: body, headers: { 'X-Inclamo-Timestamp' => '1794000000', 'X-Inclamo-Request-Id' => '4e7c2a90-6d1b-4f38-a5c2-9b1e8d3f6a07',
                                            'X-Inclamo-Signature' => 'sha256=b72c74f4156702aae0f7fa409326c14f19840cea15544d3d757b27fcae70d0b3' })
               .to_return(status: 200, body: key_answer(domain: 'example-store.myshopify.com').to_json)

        described_class.call(row: example_row, account_id: 42, scopes: StoreKeyStubs::TEN, timestamp: 1_794_000_000,
                             request_id: '4e7c2a90-6d1b-4f38-a5c2-9b1e8d3f6a07')

        expect(stub).to have_been_requested.once
      end
    end

    it "goes to the store's own address when the app gave one, and to the installation's otherwise" do
      own = 'https://other-app.example.test/keys'
      row.update!(store_access_url: "#{own}/")
      stub_store_key(address: own)

      ask

      expect(a_request(:post, store_key_url(address: own))).to have_been_made.once
      expect(key_requests).not_to have_been_made
    end

    it 'takes a new request id every time' do
      stub_store_key
      2.times { ask }

      ids = []
      expect(a_request(:post, store_key_url).with { |request| ids << request.headers['X-Inclamo-Request-Id'] }).to have_been_made.twice
      expect(ids.uniq.size).to eq(2)
    end
  end

  describe 'the scopes it asks for' do
    it 'are the ten of docs/connect-shopify.md, from the actions and the refund' do
      expect(described_class.scopes).to match_array(StoreKeyStubs::TEN)
    end

    it 'grow when an action needs a new scope' do
      stub_const('Inclamo::ShopifyConnection::ACTION_SCOPES', Inclamo::ShopifyConnection::ACTION_SCOPES.merge('returns' => %w[write_returns]))

      expect(described_class.scopes).to match_array(StoreKeyStubs::TEN + %w[write_returns])
    end
  end

  describe 'a grant' do
    it 'gives the key, its end and the scopes the app granted' do
      ends = 50.minutes.from_now.change(usec: 0)
      stub_store_key(key_answer(expires_at: ends, scopes: %w[read_orders read_customers write_orders]))

      grant = ask

      expect(grant).to have_attributes(shop_domain: StoreKeyStubs::STORE, access_token: StoreKeyStubs::KEY, expires_at: ends,
                                       scopes: %w[read_customers read_orders write_orders])
      expect(grant.inspect).not_to include(StoreKeyStubs::KEY)
    end

    it 'never takes a scope it did not ask for' do
      stub_store_key(key_answer(scopes: %w[read_customers read_orders write_themes]))

      expect(ask.scopes).to eq(%w[read_customers read_orders])
    end

    it 'refuses a key to another store' do
      stub_store_key(key_answer(domain: 'another-store.myshopify.com'))

      expect { ask }.to raise_error(Inclamo::Shopify::Error::OtherStoreKey)
    end

    it 'refuses a key with one minute left' do
      stub_store_key(key_answer(expires_at: 1.minute.from_now))

      expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error| expect(error.code).to eq('short_life') }
    end

    it 'takes a key with two minutes and more' do
      stub_store_key(key_answer(expires_at: 2.minutes.from_now + 5.seconds))

      expect(ask.access_token).to eq(StoreKeyStubs::KEY)
    end

    it 'refuses an answer without scopes, without a key or without a time' do
      [key_answer.except(:scopes), key_answer.except(:access_token), key_answer.except(:expires_at), key_answer(expires_at: 1.hour.from_now).merge(expires_at: 'soon'),
       key_answer.merge(contract: 2)].each do |answer|
        stub_store_key(answer)
        expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error| expect(error.code).to eq('unreadable') }
      end
    end
  end

  describe 'a refusal' do
    it 'is the app removed when the store does not have it' do
      stub_store_key(key_refusal(404, 'store_not_installed'))

      expect { ask }.to raise_error(Inclamo::Shopify::Error::AppKeyRefused) { |error| expect(error.reason).to eq('app_removed') }
    end

    it 'is an account mismatch when the app did not provision this account for the store' do
      stub_store_key(key_refusal(403, 'account_mismatch'))

      expect { ask }.to raise_error(Inclamo::Shopify::Error::AppKeyRefused) { |error| expect(error.reason).to eq('account_mismatch') }
    end

    it 'is no key for now on 503, 401, 422, 429 and a server error, with the wait the app asked for' do
      {
        key_refusal(503, 'store_unavailable', headers: { 'Retry-After' => '120' }) => ['store_unavailable', 120],
        key_refusal(401, 'unauthorized') => ['unauthorized', nil],
        key_refusal(422, 'contract_unsupported') => ['contract_unsupported', nil],
        key_refusal(429, 'rate_limited', headers: { 'Retry-After' => '60' }) => ['rate_limited', 60],
        { status: 500, body: '<html>oops</html>' } => ['no_answer', nil],
        { status: 404, body: '<html>Not Found</html>' } => ['no_answer', nil],
        key_refusal(403, 'forbidden') => ['no_answer', nil]
      }.each do |answer, (code, wait)|
        stub_store_key(answer)
        expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error|
          expect([error.code, error.retry_after]).to eq([code, wait])
        }
      end
    end

    it 'is no answer for a body that does not read' do
      stub_store_key({ status: 200, body: '<html>not json</html>' })

      expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error| expect(error.code).to eq('unreadable') }
    end

    it 'is no answer after a timeout or a refused connection' do
      stub_request(:post, store_key_url).to_timeout
      expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error| expect(error.code).to eq('no_answer') }

      stub_request(:post, store_key_url).to_raise(Errno::ECONNREFUSED)
      expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error| expect(error.code).to eq('no_answer') }
    end

    it 'waits at most ten seconds' do
      allow(Timeout).to receive(:timeout).and_call_original

      stub_store_key
      ask(time_limit: 60)

      expect(Timeout).to have_received(:timeout).with(10.0)
    end

    it 'does not follow a redirect' do
      stub_request(:post, store_key_url).to_return(status: 307, headers: { 'Location' => 'https://elsewhere.example.test/store-key' })

      expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) { |error| expect(error.code).to eq('redirect') }
      expect(a_request(:post, 'https://elsewhere.example.test/store-key')).not_to have_been_made
    end

    it 'refuses a private address unless private networks are allowed' do
      allow(described_class).to receive(:resolver).and_return(->(_host) { [IPAddr.new('10.0.0.7')] })
      stub = stub_store_key

      expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
      expect(stub).not_to have_been_requested
    end

    it "raises a 401 to the operator's alarm, and nothing else" do
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original
      stub_store_key(key_refusal(401, 'unauthorized'), key_refusal(503, 'store_unavailable'), key_refusal(404, 'store_not_installed'))

      3.times { ask rescue Inclamo::Shopify::Error } # rubocop:disable Style/RescueModifier

      expect(ChatwootExceptionTracker).to have_received(:new).once.with(an_instance_of(described_class::SecretRefused))
    end
  end

  describe 'where it is not asked' do
    it 'sends nothing without the secret' do
      stub = stub_store_key
      with_modified_env(INCLAMO_APP_PROVISIONING_SECRET: nil) { expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable) }
      expect(stub).not_to have_been_requested
    end

    it "sends nothing without an address of the app, or with one that is not HTTPS" do
      stub = stub_request(:post, /store-key/)
      ['', 'http://app.example.test/helpdesk', 'https://user:secret@app.example.test', 'not an address'].each do |address|
        with_modified_env(INCLAMO_APP_URL: address) do
          expect(described_class.available?(row)).to be(false)
          expect { ask }.to raise_error(Inclamo::Shopify::Error::StoreDataUnavailable)
        end
      end
      expect(stub).not_to have_been_requested
    end

    it 'is not available without encryption keys' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      expect(described_class.available?(row)).to be(false)
    end
  end

  describe 'what is kept of a request' do
    def events
      Inclamo::ProvisioningEvent.where(account_id: account.id).order(:id)
    end

    it 'records each outcome with the time, the account and the store, without a key or a signature' do
      stub_store_key(key_answer, key_refusal(404, 'store_not_installed'), key_refusal(503, 'store_unavailable'), { status: 502, body: '' }, key_answer(domain: 'another-store.myshopify.com'))

      5.times { ask rescue Inclamo::Shopify::Error } # rubocop:disable Style/RescueModifier

      expect(events.pluck(:outcome)).to eq(%w[key_granted key_refused:store_not_installed key_refused:store_unavailable key_no_answer key_invalid:other_store])
      expect(events.pluck(:shop_domain).uniq).to eq([StoreKeyStubs::STORE])
      expect(events.map(&:created_at)).to all(be_within(1.minute).of(Time.current))
      expect(events.pluck(:request_id)).to all(match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/))
      expect(events.map(&:attributes).to_json).not_to include(StoreKeyStubs::KEY, 'sha256=')
    end

    it 'logs the status, the outcome and the time taken, never the key, the signature or a body' do
      log = StringIO.new
      logger = ActiveSupport::Logger.new(log)
      allow(Rails).to receive(:logger).and_return(logger)
      stub_store_key(key_answer, key_refusal(404, 'store_not_installed'), key_refusal(401, 'unauthorized'))

      3.times { ask rescue Inclamo::Shopify::Error } # rubocop:disable Style/RescueModifier

      expect(log.string).to include('key_granted (status 200', 'key_refused:store_not_installed (status 404', 'key_refused:unauthorized (status 401')
      expect(log.string).not_to include(StoreKeyStubs::KEY, 'sha256=', StoreKeyStubs::SECRET, '"scopes"', 'for a developer')
    end
  end
end
