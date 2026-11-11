# frozen_string_literal: true

module Inclamo::Authentication::SuperAdminSession
  private

  def valid_credentials?
    return false unless super

    valid = @super_admin.active_for_authentication? && !@super_admin.mfa_enforcement_pending?
    if valid && @super_admin.mfa_enabled?
      valid = Mfa::AuthenticationService.new(
        user: @super_admin,
        otp_code: params.dig(:super_admin, :otp_code),
        backup_code: params.dig(:super_admin, :backup_code)
      ).authenticate
    end
    @error_message = I18n.t('inclamo.authentication.invalid_credentials') unless valid
    valid
  end
end
