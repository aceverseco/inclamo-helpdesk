# frozen_string_literal: true

module Custom::DeviseOverrides::PasswordsController
  private

  def reset_password_and_confirmation(recoverable)
    token = params[:reset_password_token]
    password = params[:password]
    confirmation = params[:password_confirmation]
    return false unless [token, password, confirmation].all? { |value| value.is_a?(String) && value.present? }

    # Reload under the lock: another request may have consumed the token after
    # the controller found the user. Devise's instance reset_password method
    # validates the password, but does not check the token's lifetime.
    recoverable.with_lock do
      digest = Devise.token_generator.digest(User, :reset_password_token, token)
      return false unless recoverable.reset_password_token == digest && recoverable.reset_password_period_valid?

      # Confirmation and token consumption must only persist with a valid new
      # password. A failed validation must not confirm or sign in the user.
      recoverable.skip_confirmation! unless recoverable.confirmed?
      recoverable.confirmation_token = nil
      recoverable.reset_password(password, confirmation)
    end
  end
end
