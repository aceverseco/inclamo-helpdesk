# frozen_string_literal: true

require 'rails_helper'

# Two requests for one new store at the same moment. Each thread needs its own
# database connection and has to see the other's commit, so this example runs
# outside the transaction the other examples are wrapped in and removes what it
# made.
RSpec.describe Inclamo::Provisioning::Provision do
  self.use_transactional_tests = false

  let(:domain) { "concurrent-#{SecureRandom.hex(4)}.myshopify.com" }
  let(:emails) { ["first-#{SecureRandom.hex(4)}@example.test", "second-#{SecureRandom.hex(4)}@example.test"] }

  def payload(email)
    instance_double(Inclamo::Provisioning::Payload, shop_domain: domain, shop_name: 'Concurrent Store', locale: 'en', timezone: nil,
                                                    admin_email: email, admin_name: 'Concurrent Person')
  end

  after do
    account_ids = Inclamo::ProvisionedAccount.where(shop_domain: domain).pluck(:account_id).compact
    account_ids |= Account.where(name: 'Concurrent Store').pluck(:id)
    user_ids = User.where(email: emails).pluck(:id)
    Inclamo::ProvisionedAccount.where(shop_domain: domain).delete_all
    NotificationSetting.where(account_id: account_ids).or(NotificationSetting.where(user_id: user_ids)).delete_all
    AccountUser.where(account_id: account_ids).delete_all
    CannedResponse.where(account_id: account_ids).delete_all
    Label.where(account_id: account_ids).delete_all
    Account.where(id: account_ids).delete_all
    User.where(id: user_ids).delete_all
  end

  def run_together(payloads)
    start = Queue.new
    threads = payloads.map do |one|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          described_class.new(one).call
        end
      end
    end
    payloads.size.times { start << :go }
    threads.map(&:value)
  end

  it 'ends with one account and one row, and answers both with the same identifier' do
    # The first to insert the row is held inside its transaction, so the second
    # certainly arrives while the first has not finished.
    allow(AccountBuilder).to receive(:new).and_wrap_original do |original, **arguments|
      sleep 0.5
      original.call(**arguments)
    end

    results = run_together(emails.map { |email| payload(email) })

    rows = Inclamo::ProvisionedAccount.where(shop_domain: domain)
    expect(rows.count).to eq(1)
    expect(Account.where(name: 'Concurrent Store').count).to eq(1)
    expect(results.map { |result| result.account.id }.uniq).to eq([rows.first.account_id])
    expect(results.map(&:outcome)).to contain_exactly('created', 'existed')
    expect(AccountBuilder).to have_received(:new).once

    winner = results.find { |result| result.outcome == 'created' }
    expect(winner.password_setup_url).to be_present
    expect(results.find { |result| result.outcome == 'existed' }.password_setup_url).to be_nil
    expect(rows.first.account.users.count).to eq(1)
    expect(User.where(email: emails).count).to eq(1)
  end

  it 'ends with one account when the same person asks twice at once' do
    results = run_together([payload(emails.first), payload(emails.first)])

    expect(Inclamo::ProvisionedAccount.where(shop_domain: domain).count).to eq(1)
    expect(results.map { |result| result.account.id }.uniq.size).to eq(1)
    expect(User.where(email: emails.first).count).to eq(1)
    expect(AccountUser.where(account_id: results.first.account.id).count).to eq(1)
  end
end
