# frozen_string_literal: true

# The one-time address the store app sends a staff member's browser to
# (docs/app-admin-entry.md §2): GET /inclamo/entry/<token>. The token never
# reaches the router or the request log: InclamoEntryPath takes it out of the
# path before anything else sees the request and leaves it here.
#
# A usable address signs its user in with an ordinary helpdesk session
# (Inclamo::Provisioning::EntrySession) and opens the store's account. Any
# other address, or one whose user may no longer come in this way, signs
# nobody in and shows the login page, where the password form is.
class Inclamo::EntryController < ActionController::Base
  def show
    # Only the person's browser opens the address: a HEAD (a link checker, a
    # preview) neither uses it up nor signs anybody in.
    return head(:no_content) if request.head?

    pass = Inclamo::Provisioning::EntryPass.take(request.env[InclamoEntryPath::TOKEN])
    user, account = admitted(pass)
    # Devise's sign-in for this request, as Chatwoot's one-time link does: it
    # updates the user's sign-in count and times, and refuses a user Devise
    # would not let in.
    return redirect_to('/app/login') unless user && catch(:warden) { sign_in(:user, user, store: false, bypass: false) && true } == true

    headers = Inclamo::Provisioning::EntrySession.start(user, request)
    cookies[Inclamo::Provisioning::EntrySession::SESSION_COOKIE] = Inclamo::Provisioning::EntrySession.cookie(headers, request)
    Inclamo::ProvisioningEvent.record(outcome: 'entry_used', shop_domain: pass.shop_domain, request_id: nil, user_id: user.id)
    redirect_to "/app/accounts/#{account.id}/dashboard"
  end

  private

  # The user and the account of the pass, when the user may still come in
  # this way: in the minute since the address was made the account may have
  # been suspended, the user removed from it or given a second factor.
  def admitted(pass)
    return unless pass

    user = User.find_by(id: pass.user_id)
    account = Account.find_by(id: pass.account_id)
    row = account && Inclamo::ProvisionedAccount.find_by(account_id: account.id)
    return unless user && row&.active? && !account.suspended? && AccountUser.exists?(account_id: account.id, user_id: user.id)
    return if user.mfa_enabled? || user.mfa_enforcement_pending? || !user.active_for_authentication?

    [user, account]
  end
end
