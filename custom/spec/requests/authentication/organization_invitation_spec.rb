# frozen_string_literal: true
require 'rails_helper'
require 'uri'

RSpec.describe 'Organization administrator invitation', type: :request do
  it 'delivers a self-service password link, requires MFA enrollment and scopes access to the invited organization' do
    account = create(:account, name: 'Invitation test', enforce_mfa: true)
    inviter = create(:user, account: account, role: :administrator)
    other = create(:account)
    email = 'invited-admin@example.invalid'
    password = 'PersonalPassword1!'
    previous_delivery = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      AgentBuilder.new(account: account, inviter: inviter, email: email, name: 'Invited administrator', role: :administrator).perform
    end
    user = User.find_by!(email: email)
    expect(user).not_to be_confirmed
    expect(user).not_to be_a(SuperAdmin)
    expect(user.account_users.find_by!(account: account)).to be_administrator
    expect(user.accounts.pluck(:id)).to eq([account.id])

    invitation = ActionMailer::Base.deliveries.find { |mail| mail.to == [email] }
    expect(invitation).to be_present
    expect(invitation.from).to eq([Mail::Address.new(Devise.mailer_sender).address])
    html = invitation.html_part ? invitation.html_part.decoded : invitation.body.decoded
    link = Nokogiri::HTML(html).css('a[href]').map { |node| node['href'] }.find { |href| href.include?('/auth/password/edit?') }
    expect(link).to be_present
    expect(link).to start_with(ENV.fetch('FRONTEND_URL', 'http://localhost:3000'))
    token = URI.decode_www_form(URI.parse(link).query).to_h.fetch('reset_password_token')

    put '/auth/password', params: { reset_password_token: token, password: password, password_confirmation: password }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['access-token']).to be_nil
    expect(response.parsed_body['redirect_url']).to eq('/app/login')
    expect(user.reload).to be_confirmed

    post '/auth/sign_in', params: { email: email, password: password }, as: :json
    expect(response).to have_http_status(:partial_content)
    expect(response.parsed_body['mfa_setup_required']).to be(true)
    setup_token = response.parsed_body.fetch('mfa_setup_token')
    expect(response.headers['access-token']).to be_nil

    post '/auth/sign_in', params: { mfa_setup_token: setup_token, otp_code: user.reload.current_otp }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload).to be_mfa_enabled
    expect(user.otp_backup_codes.size).to eq(10)
    headers = response.headers.slice('access-token', 'client', 'uid', 'expiry', 'token-type')
    expect(headers['access-token']).to be_present

    get "/api/v1/accounts/#{account.id}/inclamo/setup", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "/api/v1/accounts/#{other.id}/inclamo/setup", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    get '/super_admin'
    expect(response).to redirect_to(new_super_admin_session_path)

    post '/auth/sign_in', params: { email: email, password: password }, as: :json
    expect(response).to have_http_status(:partial_content)
    expect(response.parsed_body['mfa_required']).to be(true)
    expect(response.headers['access-token']).to be_nil
  ensure
    ActionMailer::Base.delivery_method = previous_delivery if previous_delivery
  end
end
