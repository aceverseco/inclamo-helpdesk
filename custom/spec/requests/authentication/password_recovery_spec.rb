# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Password recovery validation', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: 'PreviousPassword1!') }
  let(:new_password) { 'ReplacementPassword1!' }
  let(:token) do
    raw, digest = Devise.token_generator.generate(User, :reset_password_token)
    user.update!(reset_password_token: digest, reset_password_sent_at: Time.current)
    raw
  end

  def recover(password: new_password, confirmation: password, reset_token: token)
    put '/auth/password', params: {
      reset_password_token: reset_token, password: password, password_confirmation: confirmation
    }, as: :json
  end

  def expect_refused
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.headers['access-token']).to be_nil
    expect(user.reload.valid_password?('PreviousPassword1!')).to be(true)
    expect(user.reset_password_token).to be_present
  end

  it 'refuses an expired token without changing the password or consuming the token' do
    token
    user.update!(reset_password_sent_at: (Devise.reset_password_within + 1.minute).ago)
    recover
    expect_refused
  end

  it 'refuses a token without an issue date' do
    token
    user.update!(reset_password_sent_at: nil)
    recover
    expect_refused
  end

  ['', nil, 'short', 'nocapitals123'].each do |password|
    it "refuses an invalid password #{password.inspect} without confirming the user" do
      token
      user.update_columns(confirmed_at: nil, confirmation_token: 'pending-confirmation')
      recover(password: password)
      expect_refused
      expect(user.confirmed_at).to be_nil
      expect(user.confirmation_token).to eq('pending-confirmation')
    end
  end

  it 'refuses a missing password confirmation' do
    recover(confirmation: nil)
    expect_refused
  end

  it 'refuses a mismatched confirmation without confirming the user' do
    token
    user.update_columns(confirmed_at: nil, confirmation_token: 'pending-confirmation')
    recover(confirmation: 'DifferentPassword1!')
    expect_refused
    expect(user.confirmed_at).to be_nil
  end

  it 'confirms an invited user only after a valid password is saved and consumes the link once' do
    token
    user.update_columns(confirmed_at: nil, confirmation_token: 'pending-confirmation')
    recover
    expect(response).to have_http_status(:ok)
    expect(user.reload).to be_confirmed
    expect(user.valid_password?(new_password)).to be(true)
    expect(user.reset_password_token).to be_nil
    expect(user.confirmation_token).to be_nil
    recover
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.headers['access-token']).to be_nil
  end

  it 'refuses a token that was consumed after the initial lookup' do
    token
    allow(User).to receive(:find_by).and_wrap_original do |original, *args|
      found = original.call(*args)
      user.update_columns(reset_password_token: nil) if args.first.is_a?(Hash) && args.first.key?(:reset_password_token)
      found
    end
    recover
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.headers['access-token']).to be_nil
    expect(user.reload.valid_password?('PreviousPassword1!')).to be(true)
  end

  it 'preserves the second-factor requirement after setting an invited user password' do
    account.update!(enforce_mfa: true)
    recover
    expect(response).to have_http_status(:ok)
    expect(response.headers['access-token']).to be_nil
    expect(response.parsed_body['redirect_url']).to eq('/app/login')
    expect(user.reload.valid_password?(new_password)).to be(true)
  end
end
