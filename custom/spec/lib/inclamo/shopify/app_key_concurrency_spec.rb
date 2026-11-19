# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/store_key_stubs')

# Ten readers of one store at the moment its key needs renewing. Each thread
# needs its own database connection and has to see the others' commits, so
# this example runs outside the transaction the other examples are wrapped in
# and removes what it made.
RSpec.describe Inclamo::Shopify::StoreConnection do
  include_context 'with the store app for keys'

  self.use_transactional_tests = false

  let(:domain) { "concurrent-keys-#{SecureRandom.hex(4)}.myshopify.com" }
  let!(:account) { provisioned_account(domain) }
  let!(:record) { app_key_connection(account, shop_domain: domain, expires_at: expires_at) }

  after do
    Inclamo::ShopifyConnection.where(account_id: account.id).delete_all
    Inclamo::ProvisioningEvent.where(account_id: account.id).delete_all
    Inclamo::ProvisionedAccount.where(account_id: account.id).delete_all
    [NotificationSetting, AccountUser, CannedResponse, Label].each { |model| model.where(account_id: account.id).delete_all }
    Account.where(id: account.id).delete_all
  end

  def ten_readers
    start = Queue.new
    threads = Array.new(10) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          described_class.new(Inclamo::ShopifyConnection.find(record.id)).query(:shop_info)
        end
      end
    end
    10.times { start << :go }
    threads.map(&:value)
  end

  def slow_key(token)
    stub_request(:post, store_key_url(domain)).to_return do
      sleep 0.5
      { status: 200, body: key_answer(domain: domain, token: token).to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def store_answers
    stub_request(:post, shopify_graphql_url(domain)).to_return(status: 200, body: { data: shop_info_data }.to_json, headers: ShopifyStubs::JSON_HEADERS)
  end

  context 'with a key that is due for renewal and still works' do
    let(:expires_at) { 4.minutes.from_now }

    it 'answers all ten and asks the app once' do
      key = slow_key(StoreKeyStubs::NEW_KEY)
      store_answers

      expect(ten_readers).to all(include('shop'))
      expect(key).to have_been_requested.once
      expect(record.reload.access_token).to eq(StoreKeyStubs::NEW_KEY)
    end
  end

  context 'with a key that has ended' do
    let(:expires_at) { 1.minute.ago }

    it 'answers all ten with the new key and asks the app once' do
      key = slow_key(StoreKeyStubs::NEW_KEY)
      graphql = stub_request(:post, shopify_graphql_url(domain)).with(headers: { 'X-Shopify-Access-Token' => StoreKeyStubs::NEW_KEY })
                                                                 .to_return(status: 200, body: { data: shop_info_data }.to_json, headers: ShopifyStubs::JSON_HEADERS)

      expect(ten_readers).to all(include('shop'))
      expect(key).to have_been_requested.once
      expect(graphql).to have_been_requested.times(10)
    end

    it 'asks the app once when it does not answer, and every reader learns the data is unavailable' do
      key = stub_request(:post, store_key_url(domain)).to_return do
        sleep 0.5
        { status: 503, body: { error: 'store_unavailable' }.to_json }
      end
      start = Queue.new
      threads = Array.new(10) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            described_class.new(Inclamo::ShopifyConnection.find(record.id)).query(:shop_info)
          rescue Inclamo::Shopify::Error => e
            e
          end
        end
      end
      10.times { start << :go }

      expect(threads.map(&:value)).to all(be_a(Inclamo::Shopify::Error::StoreDataUnavailable))
      expect(key).to have_been_requested.once
      expect(record.reload).to be_working
    end
  end
end
