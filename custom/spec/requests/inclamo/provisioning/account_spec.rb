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
        'state' => 'active', 'outcome' => 'created', 'created_at' => account.created_at.utc.iso8601, 'admin_is_member' => true
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

    it 'takes the language as Chatwoot writes it or as a BCP 47 tag, and ignores one Chatwoot does not have' do
      { 'pt_BR' => 'pt_BR', 'pt-BR' => 'pt_BR', 'PT-br' => 'pt_BR', ' de ' => 'de', 'en-US' => 'en', 'pt-PT' => 'en', '' => 'en',
        7 => 'en' }.each_with_index do |(sent, kept), index|
        domain = "locale-#{index}.myshopify.com"
        provision(domain, shop: { locale: sent }, admin: { email: "locale-#{index}@example.test" })
        expect(response).to have_http_status(:created)
        expect(provisioned(domain).account.locale).to eq(kept), "#{sent.inspect} became #{provisioned(domain).account.locale}"
      end
    end

    it 'names a person the app gives no name after their email' do
      provision(admin: { name: nil })
      expect(User.from_email('alex@example.test').name).to eq('alex@example.test')

      provision('second-store.myshopify.com', admin: { email: 'Sam@Example.Test', name: '  ' })
      expect(response).to have_http_status(:created)
      expect(User.from_email('sam@example.test').name).to eq('sam@example.test')

      body = provisioning_body('third-store.myshopify.com', admin: { email: 'kim@example.test' })
      body[:admin].delete(:name)
      provision('third-store.myshopify.com', body: body)
      expect(response).to have_http_status(:created)
      expect(User.from_email('kim@example.test').name).to eq('kim@example.test')
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
                                                           'admin_is_member', 'password_setup_url')
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
      expect(response.parsed_body.keys).to contain_exactly('contract', 'account_id', 'helpdesk_url', 'state', 'outcome', 'created_at',
                                                           'admin_is_member')
      expect(response.parsed_body['admin_is_member']).to be(true)
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

    it 'is repeated from the stored answer; once that is gone, a new link replaces it' do
      request_id = SecureRandom.uuid
      body = provisioning_body
      url = provision(body: body, request_id: request_id).parsed_body.fetch('password_setup_url')

      expect(provision(body: body, request_id: request_id).parsed_body['password_setup_url']).to eq(url)

      Redis::Alfred.delete(Inclamo::Provisioning::RequestStore.key(request_id))
      provision(body: body, request_id: request_id)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('outcome' => 'existed', 'admin_is_member' => true)
      fresh = response.parsed_body.fetch('password_setup_url')
      expect(fresh).not_to eq(url)
      expect(set_password(url, password)).to have_http_status(:unprocessable_entity)
      expect(set_password(fresh, password)).to have_http_status(:ok)
    end

    describe 'when the first answer was lost' do
      before { @first = provision.parsed_body.fetch('password_setup_url') }

      it 'gives the administrator who never signed in a new link, and the first one stops working' do
        provision

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include('outcome' => 'existed', 'admin_is_member' => true)
        fresh = response.parsed_body.fetch('password_setup_url')
        expect(fresh).to start_with("#{ProvisioningRequests::HELPDESK_URL}/app/auth/password/edit?reset_password_token=")
        expect(set_password(@first, password)).to have_http_status(:unprocessable_entity)
        expect(set_password(fresh, password)).to have_http_status(:ok)
        expect(sign_in('alex@example.test', password)).to have_http_status(:ok)
      end

      it 'gives a user of the account who never signed in a link, whatever their role' do
        agent = create(:user, email: 'sam@example.test', account: provisioned.account, role: :agent)

        provision(admin: { email: 'sam@example.test', name: 'Sam Example' })

        expect(response.parsed_body).to include('outcome' => 'existed', 'admin_is_member' => true)
        set_password(response.parsed_body.fetch('password_setup_url'), password)
        expect(agent.reload.valid_password?(password)).to be(true)
        expect(agent.account_users.pluck(:role)).to eq(['agent'])
      end

      it 'gives none to a person who signed in on the login page' do
        set_password(@first, password)
        sign_in('alex@example.test', password)

        provision

        expect(response.parsed_body).to include('outcome' => 'existed', 'admin_is_member' => true)
        expect(response.parsed_body).not_to have_key('password_setup_url')
        expect(User.from_email('alex@example.test').valid_password?(password)).to be(true)
      end

      it 'gives none to a person who has a session from the password page' do
        set_password(@first, password)
        expect(User.from_email('alex@example.test').sign_in_count).to eq(0)

        provision

        expect(response.parsed_body).not_to have_key('password_setup_url')
      end

      it 'gives none to a person who is not a user of the account' do
        provision(admin: { email: 'sam@example.test', name: 'Sam Example' })
        expect(response.parsed_body).to include('outcome' => 'existed', 'admin_is_member' => false)
        expect(response.parsed_body).not_to have_key('password_setup_url')

        create(:user, email: 'kim@example.test', account: create(:account))
        provision(admin: { email: 'kim@example.test', name: 'Kim Example' })
        expect(response.parsed_body).to include('outcome' => 'existed', 'admin_is_member' => false)
        expect(response.parsed_body).not_to have_key('password_setup_url')
        expect(set_password(@first, password)).to have_http_status(:ok)
      end
    end

    it 'is kept out of the attempts record and of the request log, given, repeated and given again' do
      log = StringIO.new
      capture = ActiveSupport::Logger.new(log, level: :debug)
      loggers = [Rails, ActionController::Base, ActionController::API, ActiveRecord::Base]
      originals = loggers.map(&:logger)
      request_id = SecureRandom.uuid
      body = provisioning_body
      links = []
      begin
        loggers.each { |owner| owner.logger = capture }
        links << provision(body: body, request_id: request_id).parsed_body.fetch('password_setup_url')
        links << provision(body: body, request_id: request_id).parsed_body.fetch('password_setup_url')
        links << provision.parsed_body.fetch('password_setup_url')
      ensure
        loggers.zip(originals).each { |owner, original| owner.logger = original }
      end

      expect(links.uniq.size).to eq(2)
      expect(Inclamo::ProvisioningEvent.where(request_id: request_id).pluck(:outcome)).to eq(%w[created created])
      expect(log.string).to include(provisioning_path)
      links.map { |link| Rack::Utils.parse_query(URI(link).query).fetch('reset_password_token') }.each do |token|
        expect(log.string).not_to include(token)
        expect(Inclamo::ProvisioningEvent.all.flat_map { |event| event.attributes.values }.join(' ')).not_to include(token)
      end
      expect(log.string).not_to include('password/edit')
      expect(Inclamo::ProvisioningEvent.column_names).to contain_exactly('id', 'shop_domain', 'outcome', 'request_id', 'created_at')

      url = links.last
      token = Rack::Utils.parse_query(URI(url).query).fetch('reset_password_token')
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter('reset_password_token' => token, 'password_setup_url' => url,
                               'admin' => { 'email' => 'alex@example.test', 'name' => 'Alex Example' })
      expect(filtered.to_s).not_to include(token)
      expect(filtered['admin']).to eq('email' => '[FILTERED]', 'name' => '[FILTERED]')
    end
  end

  describe 'a store that has an active account' do
    # Its administrator has signed in since, so no answer below gives a link.
    before do
      provision
      User.from_email('alex@example.test').update_columns(sign_in_count: 1)
    end

    it 'answers with that account as existing and creates nothing' do
      account = provisioned.account

      expect { provision }
        .to not_change(Account, :count).and not_change(User, :count).and not_change(AccountUser, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'contract' => 1, 'account_id' => account.id, 'helpdesk_url' => ProvisioningRequests::HELPDESK_URL,
        'state' => 'active', 'outcome' => 'existed', 'created_at' => account.created_at.utc.iso8601, 'admin_is_member' => true
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

      expect(response.parsed_body).to include('outcome' => 'existed', 'account_id' => account.id, 'admin_is_member' => false)
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

  describe "the app's address for the store's key requests" do
    let(:address) { 'https://app.example.test/inclamo/store-access' }

    it 'is kept with the store when the request gives one, and is optional' do
      provision(store_access_url: address)
      expect(response).to have_http_status(:created)
      expect(provisioned.store_access_url).to eq(address)
      expect(response.parsed_body).not_to have_key('store_access_url')

      provision('second-store.myshopify.com')
      expect(provisioned('second-store.myshopify.com').store_access_url).to be_nil
      provision('third-store.myshopify.com', store_access_url: nil)
      expect(response).to have_http_status(:created)
      expect(provisioned('third-store.myshopify.com').store_access_url).to be_nil
    end

    it 'is replaced by every later request that gives one, and kept by one that does not' do
      provision(store_access_url: address)

      provision(store_access_url: 'https://app.example.test/v2/store-access')
      expect(response.parsed_body['outcome']).to eq('existed')
      expect(provisioned.store_access_url).to eq('https://app.example.test/v2/store-access')

      provision
      expect(provisioned.store_access_url).to eq('https://app.example.test/v2/store-access')

      remove_app
      provision(store_access_url: 'https://other-app.example.test/store-access')
      expect(response.parsed_body['outcome']).to eq('restored')
      expect(provisioned.store_access_url).to eq('https://other-app.example.test/store-access')
    end

    it 'is not changed by a request answered from its stored answer' do
      request_id = SecureRandom.uuid
      body = provisioning_body(store_access_url: address)
      provision(body: body, request_id: request_id)
      provisioned.update!(store_access_url: 'https://app.example.test/changed')

      provision(body: body, request_id: request_id)

      expect(provisioned.store_access_url).to eq('https://app.example.test/changed')
    end
  end
end
