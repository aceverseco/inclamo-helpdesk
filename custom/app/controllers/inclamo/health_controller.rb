# frozen_string_literal: true

# The instance's health for a monitor outside the machine: 200 when every check
# of Inclamo::Health is good, 503 with the names of the failing ones otherwise,
# and the versions that run. No sign-in, so the answer carries nothing else: no
# counts, no settings, no error text, nothing of a merchant's.
class Inclamo::HealthController < ActionController::Base
  def show
    failing = Inclamo::Health.failing
    response.headers['Cache-Control'] = 'no-store'
    render json: { status: failing.empty? ? 'ok' : 'failing',
                   failing: failing,
                   overlay_version: Inclamo::Overlay.version,
                   chatwoot_version: Chatwoot.config[:version] },
           status: failing.empty? ? :ok : :service_unavailable
  end
end
