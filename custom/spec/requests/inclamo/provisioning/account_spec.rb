# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/provisioning_requests')

RSpec.describe 'App provisioning: the store has an account', type: :request do
  include_context 'with app provisioning'

  def sign_in(email, password)
    post '/auth/sign_in', params: { email: email, password: password }, as: :json
    response
  end

  def set_password(url, password)
    token = Rack::Utils.parse_query(URI(url).query).fetch('reset_password_token')
    put '/auth/password', params: { reset_password_token: token, password: password, password_confirmation: password }, as: :json
    response
  end

  describe 'a store without an account' do
    it 'creates the account with the store\'s name, language and time zone, and answers as the contract says' do
      provision

      expect(response).to have_http_status(:created)
      account = provisioned.account
      expect(response.parsed_body.except('password_setup_url')).to eq(
        'contract' => 1, 'account_id' => account.id, 'helpdesk_url' => ProvisioningRequests::HELPDESK_URL,
        'state' => 'active', 'outcome' => 'created', 'created_at' => account.created_at.utc.iso8601
      )
      expect(account).to have_attributes(name: 'Example Store', locale: 'fr', status: 'active')
      expect(account.custom_attributes['timezone']).to eq('America/New_York')
      expect(provisioned).to have_attributes(shop_domain: ProvisioningRequests::STORE, state: 'active')
    end

    it 'builds the account as Chatwoot builds any new account' do
      builder = AccountBuilder
      allow(AccountBuilder).to receive(:new).and_call_original

      provision

      expect(builder).to have_received(:new).with(hash_including(account_name: 'Example Store', email: 'alex@example.test'))
      expect(provisioned.account.custom_attributes['onboarding_step']).to eq('account_details')
      expect(Inclamo::TeamQueue.where(account_id: provisioned.account_id)).to exist
    end

    it 'leaves out a language or a time zone it does not know, and needs neither' do
      provision(shop: { locale: 'xx', timezone: 'Mars/Olympus' })
      account = provisioned.account
      expect(account.locale).to eq('en')
      expect(account.custom_attributes).not_to have_key('timezone')

      body = provisioning_body('bare-store.myshopify.com')
      body[:shop] = body[:shop].except(:locale, :timezone)
      provision('bare-store.myshopify.com', body: body)
      expect(response).to have_http_status(:created)
      expect(provisioned('bare-store.myshopify.com').account.locale).to eq('en')
    end

    it 'makes the named person a confirmed administrator whom no password signs in, and sends no letter' do
      expect { provision }
        .to not_have_enqueued_job(ActionMailer::MailDeliveryJob).and not_change { ActionMailer::Base.deliveries.size }

      user = User.from_email('alex@example.test')
      expect(user).to have_attributes(name: 'Alex Example', email: 'alex@example.test')
      expect(user).to be_confirmed
      expect(user.confirmation_sent_at).to be_nil
      expect(user.account_users.pluck(:account_id, :role)).to eq([[provisioned.account_id, 'administrator']])

      ['', 'alex@example.test', 'Alex Example', 'Password1!', ProvisioningRequests::SECRET].each do |guess|
        expect(user.valid_password?(guess)).to be(false)
        expect(sign_in('alex@example.test', guess)).to have_http_status(:unauthorized)
      end
      expect(response.headers['access-token']).to be_nil
    end

    it 'gives every new person a different password and returns none' do
      provision
      provision('second-store.myshopify.com', admin: { email: 'sam@example.test', name: 'Sam Example' })

      alex = User.from_email('alex@example.test')
      sam = User.from_email('sam@example.test')
      expect(alex.encrypted_password).to be_present
      expect(alex.encrypted_password).not_to eq(sam.encrypted_password)
      expect(response.parsed_body.keys).to contain_exactly('contract', 'account_id', 'helpdesk_url', 'state', 'outcome', 'created_at',
                                                           'password_setup_url')
    end
  end

  describe 'a person the installation already knows' do
    let(:other_account) { create(:account, name: 'Another Store') }
    let!(:known) { create(:user, email: 'alex@example.test', name: 'Alexandra', password: 'KnownPassword1!', account: other_account, role: :agent) }

    it 'adds the new account to their user and touches nothing else of theirs' do
      encrypted = known.encrypted_password

      expect { provision(admin: { email: 'Alex@Example.Test', name: 'Somebody Else' }) }
        .to not_change(User, :count).and not_have_enqueued_job(ActionMailer::MailDeliveryJob)

      expect(response).to have_http_status(:created)
      known.reload
      expect(known).to have_attributes(name: 'Alexandra', encrypted_password: encrypted, reset_password_token: nil)
      expect(known.account_users.pluck(:account_id, :role))
        .to contain_exactly([other_account.id, 'agent'], [provisioned.account_id, 'administrator'])
      expect(sign_in('alex@example.test', 'KnownPassword1!')).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'accounts').pluck('id')).to contain_exactly(other_account.id, provisioned.account_id)
    end

    it 'gives no password link and reveals nothing else about the email being known' do
      provision

      expect(response.parsed_body).not_to have_key('password_setup_url')
      expect(response.parsed_body.keys).to contain_exactly('contract', 'account_id', 'helpdesk_url', 'state', 'outcome', 'created_at')
      expect(known.reload.valid_password?('KnownPassword1!')).to be(true)
    end
  end

  describe 'the one-time password link' do
    let(:password) { 'OwnPassword1!' }

    it 'is the helpdesk\'s own password page with a token for that user' do
      provision

      url = URI(response.parsed_body.fetch('password_setup_url'))
      expect("#{url.scheme}://#{url.host}#{url.path}").to eq("#{ProvisioningRequests::HELPDESK_URL}/app/auth/password/edit")
      expect(Rack::Utils.parse_query(url.query).keys).to eq(['reset_password_token'])
    end

    it 'sets a password that then signs in and shows the new account' do
      provision
      account_id = response.parsed_body.fetch('account_id')

      expect(set_password(response.parsed_body.fetch('password_setup_url'), password)).to have_http_status(:ok)

      expect(sign_in('alex@example.test', password)).to have_http_status(:ok)
      expect(response.headers['access-token']).to be_present
      expect(response.parsed_body.dig('data', 'accounts').pluck('id')).to eq([account_id])
    end

    it 'sets a password for that user only' do
      bystander = create(:user, email: 'sam@example.test', password: 'Bystander1!', account: create(:account))
      provision

      set_password(response.parsed_body.fetch('password_setup_url'), password)

      expect(bystander.reload.valid_password?('Bystander1!')).to be(true)
      expect(bystander.valid_password?(password)).to be(false)
    end

    it 'is refused on a second use and leaves the password as it was set' do
      provision
      url = response.parsed_body.fetch('password_setup_url')
      set_password(url, password)

      expect(set_password(url, 'AnotherPassword2!')).to have_http_status(:unprocessable_entity)

      user = User.from_email('alex@example.test')
      expect(user.valid_password?(password)).to be(true)
      expect(user.valid_password?('AnotherPassword2!')).to be(false)
    end

    it 'is refused after its time has passed, and sets no password' do
      provision
      url = response.parsed_body.fetch('password_setup_url')

      travel_to((Devise.reset_password_within + 1.minute).from_now) do
        expect(set_password(url, password)).to have_http_status(:unprocessable_entity)
      end

      expect(User.from_email('alex@example.test').valid_password?(password)).to be(false)
      expect(sign_in('alex@example.test', password)).to have_http_status(:unauthorized)
    end

    it 'still works just before its time has passed' do
      provision
      url = response.parsed_body.fetch('password_setup_url')

      travel_to((Devise.reset_password_within - 1.minute).from_now) do
        expect(set_password(url, password)).to have_http_status(:ok)
      end
    end

    it 'is repeated only from the stored answer, and is gone with it' do
      request_id = SecureRandom.uuid
      body = provisioning_body
      url = provision(body: body, request_id: request_id).parsed_body.fetch('password_setup_url')

      expect(provision(body: body, request_id: request_id).parsed_body['password_setup_url']).to eq(url)

      Redis::Alfred.delete(Inclamo::Provisioning::RequestStore.key(request_id))
      provision(body: body, request_id: request_id)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['outcome']).to eq('existed')
      expect(response.parsed_body).not_to have_key('password_setup_url')
      expect(set_password(url, password)).to have_http_status(:ok)
    end

    it 'is not given on an account that existed, to anybody' do
      provision
      provision
      expect(response.parsed_body).not_to have_key('password_setup_url')

      provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
      expect(response.parsed_body['outcome']).to eq('existed')
      expect(response.parsed_body).not_to have_key('password_setup_url')
    end

    it 'is kept out of the attempts record and of the request log' do
      log = StringIO.new
      capture = ActiveSupport::Logger.new(log, level: :debug)
      loggers = [Rails, ActionController::Base, ActionController::API, ActiveRecord::Base]
      originals = loggers.map(&:logger)
      begin
        loggers.each { |owner| owner.logger = capture }
        provision
      ensure
        loggers.zip(originals).each { |owner, original| owner.logger = original }
      end

      url = response.parsed_body.fetch('password_setup_url')
      token = Rack::Utils.parse_query(URI(url).query).fetch('reset_password_token')
      expect(log.string).to include(provisioning_path)
      expect(log.string).not_to include(token)
      expect(log.string).not_to include('password/edit')
      expect(Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values }.join(' ')).not_to include(token)
      expect(Inclamo::ProvisioningEvent.column_names).to contain_exactly('id', 'shop_domain', 'outcome', 'request_id', 'created_at')

      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter('reset_password_token' => token, 'password_setup_url' => url,
                               'admin' => { 'email' => 'alex@example.test', 'name' => 'Alex Example' })
      expect(filtered.to_s).not_to include(token)
      expect(filtered['admin']).to eq('email' => '[FILTERED]', 'name' => '[FILTERED]')
    end
  end

  describe 'a store that has an active account' do
    before { provision }

    it 'answers with that account as existing and creates nothing' do
      account = provisioned.account

      expect { provision }
        .to not_change(Account, :count).and not_change(User, :count).and not_change(AccountUser, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'contract' => 1, 'account_id' => account.id, 'helpdesk_url' => ProvisioningRequests::HELPDESK_URL,
        'state' => 'active', 'outcome' => 'existed', 'created_at' => account.created_at.utc.iso8601
      )
      expect(Inclamo::ProvisionedAccount.where(shop_domain: ProvisioningRequests::STORE).count).to eq(1)
    end

    it 'does not change the name, the language or the time zone the team has' do
      account = provisioned.account
      account.update!(name: 'Renamed By The Team')

      provision(shop: { name: 'Example Store Ltd', locale: 'de', timezone: 'Europe/Berlin' })

      expect(response.parsed_body['outcome']).to eq('existed')
      expect(account.reload).to have_attributes(name: 'Renamed By The Team', locale: 'fr')
      expect(account.custom_attributes['timezone']).to eq('America/New_York')
    end

    it 'does not add another person who asks, whether or not the installation knows them' do
      account = provisioned.account
      known = create(:user, email: 'known@example.test', account: create(:account))

      expect do
        provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
        provision(admin: { email: 'known@example.test', name: 'Known Person' })
      end.to not_change(User, :count).and not_change(AccountUser, :count)

      expect(response.parsed_body).to include('outcome' => 'existed', 'account_id' => account.id)
      expect(User.from_email('sam@example.test')).to be_nil
      expect(account.users.pluck(:email)).to eq(['alex@example.test'])
      expect(known.reload.accounts).not_to include(account)
    end

    it 'finds the account whatever the case of the domain' do
      provision('EXAMPLE-STORE.myshopify.com', body: provisioning_body('Example-Store.MYSHOPIFY.com'))

      expect(response.parsed_body).to include('outcome' => 'existed', 'account_id' => provisioned.account_id)
      expect(Inclamo::ProvisionedAccount.count).to eq(1)
    end

    it 'keeps another store out of this account' do
      provision('second-store.myshopify.com')

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['account_id']).not_to eq(provisioned.account_id)
      expect(response.parsed_body).not_to have_key('password_setup_url')
      expect(User.from_email('alex@example.test').accounts.count).to eq(2)
    end
  end
end
