# frozen_string_literal: true

require 'rails_helper'

# The entry's session is made of Chatwoot's own pieces (Inclamo::Provisioning::
# EntrySession). These fail first when an upstream release changes one of
# them: then the entry's session must be checked against Chatwoot's sign-in
# again before the release is taken.
RSpec.describe Inclamo::Provisioning::EntrySession do
  let(:user) { create(:user) }
  let(:request) { ActionDispatch::TestRequest.create('HTTP_USER_AGENT' => 'Mozilla/5.0 Safari/605.1.15', 'REMOTE_ADDR' => '203.0.113.7') }

  it 'relies on the session limit routines of Chatwoot\'s sign-in, which take only the user' do
    controller = DeviseOverrides::SessionsController
    %i[sessions_limit_reached? evict_oldest_session evict_oldest_token active_token_count].each do |name|
      expect(controller.private_method_defined?(name)).to be(true), "DeviseOverrides::SessionsController##{name} is gone"
      expect(controller.instance_method(name).parameters).to eq([[:req, :user]])
    end
  end

  it 'relies on the session row Chatwoot lists, and on devise-token-auth\'s token and headers' do
    expect(UserSessionTrackingService.instance_method(:initialize).parameters).to eq([[:keyreq, :user], [:keyreq, :request], [:keyreq, :client_id]])
    expect(User.instance_method(:create_token).parameters).to include([:key, :client], [:key, :lifespan])
    expect(User.instance_method(:build_auth_headers).parameters.first).to eq([:req, :token])
  end

  it 'gives the dashboard the cookie its script reads, with the five headers it reads' do
    store = Rails.root.join('app/javascript/dashboard/store/utils/api.js').read
    helper = Rails.root.join('app/javascript/dashboard/helper/APIHelper.js').read

    expect(store).to include("Cookies.set('#{described_class::SESSION_COOKIE}', JSON.stringify(response.headers)")
    described_class::HEADERS.each { |name| expect(helper).to match(/'?#{Regexp.escape(name)}'?(?::|,)/) }
  end

  it 'starts a session with a token of the usual lifespan and a listed session row' do
    headers = described_class.start(user, request)

    expect(headers.keys).to contain_exactly('access-token', 'token-type', 'client', 'expiry', 'uid')
    expect(user.reload.valid_token?(headers['access-token'], headers['client'])).to be(true)
    expect(user.user_sessions.find_by(client_id: headers['client'])).to have_attributes(ip_address: '203.0.113.7')
    expect(Time.zone.at(headers['expiry'].to_i)).to be_within(1.minute).of(DeviseTokenAuth.token_lifespan.from_now)
  end

  it 'makes room at the limit as Chatwoot does for a client that cannot show the list of sessions' do
    with_modified_env(MAX_USER_SESSIONS: '2') do
      2.times do |index|
        user.tokens = user.tokens.merge("c#{index}" => { 'token' => 'x', 'expiry' => (30 + index).days.from_now.to_i })
        user.save!
      end

      headers = described_class.start(user, request)

      expect(user.reload.tokens.keys).to contain_exactly('c1', headers['client'])
    end
  end
end
