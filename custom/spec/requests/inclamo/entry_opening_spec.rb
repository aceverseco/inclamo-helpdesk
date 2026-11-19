# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/entry_requests')

# Opening the one-time address (docs/app-admin-entry.md §2): it signs in the
# user it was made for with an ordinary session, opens the store's account,
# works once and for a minute, and leaves the token in no log.
RSpec.describe 'App admin entry: opening the address', type: :request do
  include_context 'with app admin entry'

  let!(:account) { store_account }
  let!(:alex) { member(account, 'alex@example.test', role: :administrator) }

  def given_url(email = 'alex@example.test', domain = ProvisioningRequests::STORE)
    ask_entry(domain, staff: { email: email })
    expect(response).to have_http_status(:ok)
    entry_url
  end

  def expect_login_page
    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to end_with('/app/login')
    expect(dashboard_session).to be_nil
  end

  def profile(session)
    get '/api/v1/profile', headers: session.slice('access-token', 'token-type', 'client', 'expiry', 'uid')
    response
  end

  it 'signs the user in with the dashboard\'s session and opens the store\'s account' do
    url = given_url

    open_entry(url)

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to end_with("/app/accounts/#{account.id}/dashboard")
    session = dashboard_session
    expect(session.keys).to contain_exactly('access-token', 'token-type', 'client', 'expiry', 'uid')
    expect(session['token-type']).to eq('Bearer')
    expect(profile(session)).to have_http_status(:ok)
    expect(response.parsed_body).to include('email' => 'alex@example.test', 'id' => alex.id)
  end

  it 'sets the cookie as the dashboard sets it: readable by its script, for the whole site, until the session ends' do
    open_entry(given_url)

    cookie = Array(response.headers['set-cookie']).join("\n").split("\n").find { |line| line.start_with?('cw_d_session_info=') }
    attributes = cookie.split(';').map(&:strip).map(&:downcase)
    expect(attributes).to include('path=/', 'samesite=lax')
    expect(attributes).not_to include('httponly')
    expires = Time.zone.parse(attributes.find { |part| part.start_with?('expires=') }.delete_prefix('expires='))
    expect(expires).to be_within(1.minute).of(Time.zone.at(dashboard_session['expiry'].to_i))
    expect(expires).to be > 1.month.from_now
  end

  it 'serves the address with no referrer and nothing cached, whether or not it works' do
    open_entry(given_url)
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    expect(response.headers['Cache-Control']).to eq('no-store')

    open_entry("#{ProvisioningRequests::HELPDESK_URL}/inclamo/entry/#{SecureRandom.urlsafe_base64(32)}")
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'gives an agent the agent\'s rights' do
    member(account, 'sam@example.test', role: :agent)
    open_entry(given_url('sam@example.test'))
    session = dashboard_session

    profile(session)
    expect(response.parsed_body['accounts']).to contain_exactly(include('id' => account.id, 'role' => 'agent'))
    post "/api/v1/accounts/#{account.id}/inboxes", params: { name: 'Not mine to add', channel: { type: 'api' } },
                                                   headers: session.slice('access-token', 'token-type', 'client', 'expiry', 'uid'), as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'opens the named store\'s account for a user of two accounts who last worked in the other' do
    other = store_account('other-store.myshopify.com')
    create(:account_user, account: other, user: alex, role: :administrator)
    AccountUser.find_by(account: other, user: alex).update!(active_at: Time.current)
    AccountUser.find_by(account: account, user: alex).update!(active_at: 1.day.ago)

    open_entry(given_url)

    expect(response.headers['Location']).to end_with("/app/accounts/#{account.id}/dashboard")
    open_entry(given_url('alex@example.test', 'other-store.myshopify.com'))
    expect(response.headers['Location']).to end_with("/app/accounts/#{other.id}/dashboard")
  end

  describe 'once and briefly' do
    it 'signs nobody in the second time, and shows the login page' do
      url = given_url
      open_entry(url)
      expect(dashboard_session).to be_present

      open_entry(url)

      expect_login_page
      expect(entry_keys).to be_empty
    end

    it 'signs nobody in once its minute has passed' do
      url = given_url
      expect(Redis::Alfred.ttl(entry_keys.first)).to be_between(1, 60)

      travel_to(61.seconds.from_now) { open_entry(url) }

      expect_login_page
    end

    it 'is not used up by a HEAD request, which signs nobody in' do
      url = given_url

      head URI.parse(url).path
      expect(response).to have_http_status(:no_content)
      expect(dashboard_session).to be_nil

      open_entry(url)
      expect(dashboard_session).to be_present
    end

    it 'is taken by deleting it: whoever deleted it has it, and nobody after' do
      token = given_url.split('/').last

      expect(Inclamo::Provisioning::EntryPass.take(token)).to have_attributes(user_id: alex.id, account_id: account.id)
      expect(Inclamo::Provisioning::EntryPass.take(token)).to be_nil

      token = given_url.split('/').last
      key = Inclamo::Provisioning::EntryPass.key(token)
      # Another opening deleted it between this one's read and its delete.
      allow(Redis::Alfred).to receive(:get).and_wrap_original { |original, *args| original.call(*args).tap { Redis::Alfred.delete(key) } }
      expect(Inclamo::Provisioning::EntryPass.take(token)).to be_nil
    end

    it 'signs nobody in with a token that was never given, a changed token, or none' do
      url = given_url

      open_entry("#{url}x")
      expect_login_page
      open_entry(url.sub(%r{/([^/])([^/]*)\z}) { "/#{Regexp.last_match(1) == 'A' ? 'B' : 'A'}#{Regexp.last_match(2)}" })
      expect_login_page
      get '/inclamo/entry'
      expect_login_page
      get '/inclamo/entry/'
      expect_login_page

      open_entry(url)
      expect(dashboard_session).to be_present
    end

    it 'is not a Chatwoot sign-in link: the token with another user\'s email signs nobody in' do
      member(account, 'sam@example.test', role: :agent)
      token = given_url.split('/').last

      post '/auth/sign_in', params: { email: 'sam@example.test', sso_auth_token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)
      post '/auth/sign_in', params: { email: 'alex@example.test', sso_auth_token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context 'when the user may no longer come in this way since the address was made' do
      it 'signs nobody in once the account was suspended' do
        url = given_url
        remove_app

        open_entry(url)

        expect_login_page
      end

      it 'signs nobody in once the user left the account' do
        url = given_url
        AccountUser.where(account: account, user: alex).delete_all

        open_entry(url)

        expect_login_page
      end

      it 'signs nobody in once the user turned two-factor authentication on' do
        url = given_url
        alex.update!(otp_required_for_login: true)

        open_entry(url)

        expect_login_page
      end
    end
  end

  describe 'the session' do
    it 'is listed among the user\'s sessions, as the current one' do
      expect { open_entry(given_url) }.to change(alex.user_sessions, :count).by(1)
      session = dashboard_session

      get '/api/v1/profile/sessions', headers: session.slice('access-token', 'token-type', 'client', 'expiry', 'uid')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to contain_exactly(include('current' => true))
      expect(alex.reload.user_sessions.last).to have_attributes(client_id: session['client'], user_agent: EntryRequests::BROWSER)
    end

    it 'lasts as long as a password session, and counts as a sign-in' do
      expect { open_entry(given_url) }.to change { alex.reload.sign_in_count }.by(1)

      expiry = alex.reload.tokens.fetch(dashboard_session['client'])['expiry']
      expect(Time.zone.at(expiry)).to be_within(1.minute).of(DeviseTokenAuth.token_lifespan.from_now)
    end

    it 'counts against the limit of sessions per user: at the limit the oldest session gives way' do
      with_modified_env(MAX_USER_SESSIONS: '3') do
        3.times do |index|
          alex.tokens = alex.tokens.merge("old#{index}" => { 'token' => 'x', 'expiry' => 30.days.from_now.to_i })
          alex.save!
          alex.user_sessions.create!(client_id: "old#{index}", last_activity_at: (3 - index).days.ago)
        end

        open_entry(given_url)

        expect(dashboard_session).to be_present
        expect(alex.reload.tokens.keys).not_to include('old0')
        expect(alex.tokens.keys).to include('old1', 'old2', dashboard_session['client'])
        expect(alex.user_sessions.exists?(client_id: 'old0')).to be(false)
      end
    end

    it 'ends when the user signs out' do
      open_entry(given_url)
      session = dashboard_session.slice('access-token', 'token-type', 'client', 'expiry', 'uid')

      delete '/auth/sign_out', headers: session
      expect(response).to have_http_status(:ok)

      get '/api/v1/profile', headers: session
      expect(response).to have_http_status(:unauthorized)
    end

    it 'leaves the user\'s other sessions as they are' do
      post '/auth/sign_in', params: { email: 'alex@example.test', password: 'Password1!' }, as: :json
      password_session = response.headers.to_h.slice('access-token', 'token-type', 'client', 'expiry', 'uid')

      open_entry(given_url)

      get '/api/v1/profile', headers: password_session
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'the logs' do
    it 'never hold the token, the address or the email' do
      url = nil
      text = logged do
        url = given_url
        open_entry(url)
        open_entry(url)
      end
      token = url.split('/').last

      expect(text).to include('/inclamo/entry')
      expect(text).not_to include(token)
      expect(text).not_to include(url)
      expect(text).not_to include('alex@example.test')
      expect(text).not_to include('alex%40example.test')
    end
  end

  it 'records the use of an address with the user and the store, and nothing for an address that does not work' do
    url = given_url
    open_entry(url)
    open_entry(url)

    expect(outcomes).to eq(%w[created entry_given entry_used])
    expect(Inclamo::ProvisioningEvent.order(:id).last).to have_attributes(outcome: 'entry_used', user_id: alex.id, request_id: nil,
                                                                          shop_domain: ProvisioningRequests::STORE)
  end
end
