# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/entry_requests')

# The store app asks to let a staff member in (docs/app-admin-entry.md): what
# the body must say, who gets an address and who is refused with what words,
# and what the address is.
RSpec.describe 'App admin entry: the request', type: :request do
  include_context 'with app admin entry'

  let!(:account) { store_account }
  let!(:alex) { member(account, 'alex@example.test', role: :administrator) }

  def expect_refused(status, error, message = nil)
    expect(response).to have_http_status(status)
    expect(response.parsed_body['error']).to eq(error)
    expect(response.parsed_body['message']).to eq(message) if message
    expect(response.parsed_body).not_to have_key('entry_url')
    expect(entry_keys).to be_empty
  end

  describe 'the body' do
    it 'refuses a staff member without an email, or with one that does not read as an email' do
      [{ email: nil }, { email: '' }, { email: 'not an email' }, { email: 42 }, { email: "#{'a' * 250}@example.test" }].each do |staff|
        ask_entry(staff: staff)
        expect_refused(:unprocessable_entity, 'staff_email_missing')
        expect(response.parsed_body['message']).to be_present
      end
      ask_entry(body: { contract: 1 })
      expect_refused(:unprocessable_entity, 'staff_email_missing')
    end

    it 'refuses an email whose verification is not stated as true' do
      [false, nil, 'true', 1].each do |verified|
        ask_entry(staff: { email_verified: verified })
        expect_refused(:unprocessable_entity, 'staff_email_unverified')
      end
      ask_entry(body: { contract: 1, staff: { email: 'alex@example.test' } })
      expect_refused(:unprocessable_entity, 'staff_email_unverified')
    end

    it 'refuses a contract version it does not speak, and a body that is not a JSON object' do
      [{ contract: 2, staff: { email: 'alex@example.test', email_verified: true } }, { staff: {} }, '[1]', 'not json', ''].each do |body|
        ask_entry(body: body)
        expect_refused(:unprocessable_entity, 'contract_unsupported')
      end
    end

    it 'reads the email as Chatwoot does: without spaces around it, whatever the case of its letters' do
      ask_entry(staff: { email: '  Alex@Example.TEST ' })

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'who gets in' do
    it 'gives an administrator of the store\'s account an address' do
      ask_entry

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to contain_exactly('contract', 'entry_url', 'expires_in')
      expect(response.parsed_body).to include('contract' => 1, 'expires_in' => 60)
    end

    it 'gives an agent of the store\'s account an address' do
      member(account, 'sam@example.test', role: :agent)

      ask_entry(staff: { email: 'sam@example.test' })

      expect(response).to have_http_status(:ok)
      expect(entry_url).to start_with("#{ProvisioningRequests::HELPDESK_URL}/inclamo/entry/")
    end

    it 'gives an unknown email and a user of another account one answer, and creates nothing' do
      other = store_account('other-store.myshopify.com')
      member(other, 'pat@example.test', role: :administrator)
      not_a_user = { 'error' => 'not_a_user',
                     'message' => "This email is not a user of this helpdesk account. Ask the account's administrator to invite you." }

      expect do
        ask_entry(staff: { email: 'nobody@example.test' })
        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq(not_a_user)
        ask_entry(staff: { email: 'pat@example.test' })
        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq(not_a_user)
      end.to not_change(User, :count).and not_change(AccountUser, :count).and not_change(Account, :count)

      expect(User.from_email('nobody@example.test')).to be_nil
      expect(AccountUser.exists?(account: account, user: User.from_email('pat@example.test'))).to be(false)
      expect(entry_keys).to be_empty
    end

    it 'says that a store without an account has none' do
      ask_entry('never-installed.myshopify.com')
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'no_account')

      ask_entry('not-a-shop.example.com')
      expect(response).to have_http_status(:not_found)
      expect(entry_keys).to be_empty
    end

    it 'says that the account is suspended when the app was removed, and lets nobody in' do
      remove_app

      ask_entry

      expect_refused(:forbidden, 'account_suspended', 'This helpdesk account is suspended.')
    end

    it 'treats an account suspended by hand as suspended, and a store whose account is being erased as having none' do
      account.update!(status: :suspended)
      ask_entry
      expect_refused(:forbidden, 'account_suspended')

      account.update!(status: :active)
      provisioned.update!(state: 'erasing', account_id: nil)
      ask_entry
      expect_refused(:not_found, 'no_account')
    end

    it 'checks the account before the person: a suspended account says so to an unknown email too' do
      remove_app

      ask_entry(staff: { email: 'nobody@example.test' })

      expect_refused(:forbidden, 'account_suspended')
    end

    it 'refuses a user with two-factor authentication, whose password and code still work' do
      alex.update!(password: 'Password1!')
      alex.enable_two_factor!
      alex.update!(otp_required_for_login: true)

      ask_entry

      expect_refused(:forbidden, 'two_factor',
                     "Two-factor authentication is on for this user. Sign in on the helpdesk's login page with your password and code.")
      post '/auth/sign_in', params: { email: 'alex@example.test', password: 'Password1!' }, as: :json
      expect(response).to have_http_status(:partial_content)
      expect(response.parsed_body).to include('mfa_required' => true)
    end

    it 'refuses a user an account of theirs requires two-factor authentication of, as two_factor' do
      other = create(:account)
      create(:account_user, account: other, user: alex)
      other.update!(enforce_mfa: true)
      expect(alex.reload.mfa_enforcement_pending?).to be(true)

      ask_entry

      expect_refused(:forbidden, 'two_factor')
    end

    it 'refuses a user Chatwoot would not let sign in, as not a user' do
      allow_any_instance_of(User).to receive(:active_for_authentication?).and_return(false) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(User).to receive(:inactive_message).and_return(:locked) # rubocop:disable RSpec/AnyInstance

      ask_entry

      expect_refused(:forbidden, 'not_a_user')
    end
  end

  describe 'a user with a pending invitation' do
    let!(:invited) { create(:user, email: 'ivy@example.test', account: account, role: :agent, skip_confirmation: false) }

    it 'is confirmed before the address is made, without a password and without a letter' do
      expect(invited.reload.confirmed?).to be(false)
      password = invited.encrypted_password
      ActionMailer::Base.deliveries.clear

      expect { ask_entry(staff: { email: 'ivy@example.test' }) }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

      expect(response).to have_http_status(:ok)
      expect(invited.reload.confirmed?).to be(true)
      expect(invited.encrypted_password).to eq(password)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe 'the address' do
    it 'carries an opaque token and nothing about the person or the account' do
      ask_entry

      # The helpdesk's own address, a path of 43 random characters and no query.
      expect(entry_url).to match(%r{\A#{Regexp.escape(ProvisioningRequests::HELPDESK_URL)}/inclamo/entry/[A-Za-z0-9_-]{43}\z})
      expect(entry_url.delete_prefix(ProvisioningRequests::HELPDESK_URL)).not_to include('alex')
    end

    it 'is kept in Redis under a digest of its token, with a life of at most 60 seconds' do
      ask_entry
      token = entry_url.split('/').last

      expect(entry_keys).to eq([Inclamo::Provisioning::EntryPass.key(token)])
      expect(entry_keys.first).not_to include(token)
      expect(Redis::Alfred.ttl(entry_keys.first)).to be_between(1, 60)
      stored = JSON.parse(Redis::Alfred.get(entry_keys.first))
      expect(stored).to eq('user_id' => alex.id, 'account_id' => account.id, 'shop_domain' => ProvisioningRequests::STORE)
    end

    it 'is a new address for every request' do
      ask_entry
      first = entry_url
      ask_entry

      expect(entry_url).not_to eq(first)
      expect(entry_keys.size).to eq(2)
    end
  end
end
