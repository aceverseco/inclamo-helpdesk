# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'inclamo:provisioning:link', type: :request do
  include_context 'with app provisioning'

  let(:account) { create(:account, name: 'Made By Hand') }
  let(:task) do
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    load Rails.root.join('custom/lib/tasks/inclamo_provisioning.rake') unless Rake::Task.task_defined?('inclamo:provisioning:link')
    Rake::Task['inclamo:provisioning:link'].tap(&:reenable)
  end

  def link(domain, account_id)
    task.reenable
    task.invoke(domain, account_id.to_s)
  end

  it 'ties an account made by hand to its store, so the store\'s later request finds it' do
    create(:user, account: account, role: :administrator)

    expect { link('Example-Store.myshopify.com', account.id) }.to output(/example-store\.myshopify\.com is linked to account #{account.id}/).to_stdout

    expect { provision }.to not_change(Account, :count).and not_change(User, :count).and not_change(AccountUser, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('outcome' => 'existed', 'account_id' => account.id, 'state' => 'active')
    expect(response.parsed_body).not_to have_key('password_setup_url')
    expect(account.reload.name).to eq('Made By Hand')
  end

  it 'refuses a domain that is already linked' do
    link(ProvisioningRequests::STORE, account.id)
    other = create(:account)

    expect { link('EXAMPLE-STORE.myshopify.com', other.id) }.to raise_error(SystemExit).and output(/already linked/).to_stderr
    expect(provisioned.account_id).to eq(account.id)
    expect(Inclamo::ProvisionedAccount.count).to eq(1)
  end

  it 'refuses an account that is already linked, also one the app created' do
    link(ProvisioningRequests::STORE, account.id)
    expect { link('other-store.myshopify.com', account.id) }.to raise_error(SystemExit).and output(/already linked/).to_stderr

    provision('third-store.myshopify.com')
    created = provisioned('third-store.myshopify.com').account_id
    expect { link('fourth-store.myshopify.com', created) }.to raise_error(SystemExit).and output(/already linked/).to_stderr
    expect(Inclamo::ProvisionedAccount.count).to eq(2)
  end

  it 'refuses a domain that is not a store\'s and an account that does not exist' do
    expect { link('shop.example.com', account.id) }.to raise_error(SystemExit).and output(/not a myshopify.com domain/).to_stderr
    expect { link(ProvisioningRequests::STORE, 0) }.to raise_error(SystemExit).and output(/no account/).to_stderr
    expect { link(ProvisioningRequests::STORE, 'first') }.to raise_error(SystemExit).and output(/no account/).to_stderr
    expect(Inclamo::ProvisionedAccount.count).to eq(0)
  end

  it 'links a suspended account as suspended, and the store\'s request restores it' do
    account.update!(status: :suspended)
    link(ProvisioningRequests::STORE, account.id)

    provision

    expect(response.parsed_body).to include('outcome' => 'restored', 'account_id' => account.id)
    expect(account.reload).to be_active
  end
end
