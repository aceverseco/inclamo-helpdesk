# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'SuperAdmin second factor', type: :request do
  let(:password) { 'AdminPassword1!' }
  let(:admin) { create(:super_admin, password: password) }

  before do
    # Backend CI has no frontend bundle; exercise the actual login form without
    # making its asset tags start a Vite build.
    allow_any_instance_of(ActionView::Base).to receive(:vite_client_tag).and_return('')
    allow_any_instance_of(ActionView::Base).to receive(:vite_javascript_tag).and_return('')
    allow_any_instance_of(ActionView::Base).to receive(:vite_stylesheet_tag).and_return('')
    allow_any_instance_of(ActionView::Base).to receive(:vite_asset_path).and_return('/test-font.woff2')
  end

  def enroll
    admin.enable_two_factor!
    admin.mfa_service.verify_and_activate!
  end

  def login(**extra)
    post '/super_admin/sign_in', params: { super_admin: { email: admin.email, password: password }.merge(extra) }
  end

  def expect_refused
    expect(response).to redirect_to(super_admin_session_path)
    get '/super_admin'
    expect(response).to redirect_to(new_super_admin_session_path)
  end

  it 'offers authenticator and recovery inputs without prefilled secrets' do
    get '/super_admin/sign_in'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('super_admin[otp_code]', 'super_admin[backup_code]', 'one-time-code')
  end

  it 'does not require an unconfigured second factor' do
    login
    expect(response).to redirect_to(super_admin_root_path)
  end

  it 'refuses a password without the enrolled second factor' do
    enroll
    login
    expect_refused
  end

  it 'refuses an invalid second factor' do
    enroll
    login(otp_code: 'invalid')
    expect_refused
  end

  it 'accepts the authenticator code and refuses reuse' do
    enroll
    code = admin.current_otp
    login(otp_code: code)
    expect(response).to redirect_to(super_admin_root_path)
    delete '/super_admin/sign_out'
    login(otp_code: code)
    expect_refused
  end

  it 'accepts a recovery code once' do
    codes = enroll
    login(backup_code: codes.first)
    expect(response).to redirect_to(super_admin_root_path)
    delete '/super_admin/sign_out'
    login(backup_code: codes.first)
    expect_refused
  end

  it 'does not consume the second factor when the password is wrong' do
    codes = enroll
    login(password: 'IncorrectPassword1!', backup_code: codes.first)
    expect_refused
    expect(admin.reload.otp_backup_codes).to include(codes.first)
  end

  it 'refuses an unconfirmed administrator' do
    admin.update_columns(confirmed_at: nil)
    login
    expect_refused
  end

  it 'refuses bypassing an organization requirement before MFA enrollment' do
    account = create(:account, enforce_mfa: true)
    create(:account_user, account: account, user: admin, role: :administrator)
    login
    expect_refused
  end
end
