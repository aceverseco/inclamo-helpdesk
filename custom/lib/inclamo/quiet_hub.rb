# frozen_string_literal: true

module Inclamo
  # Chatwoot's hub client, silenced. An instance reports nothing about itself:
  # no daily version check (which carries the host name and, unless telemetry
  # is off, counts), no registration of the owner at onboarding, no events.
  # Prepended to ChatwootHub's singleton class in custom/config/overlay.rb, so
  # each of the three returns before Chatwoot's method builds a request.
  #
  # Push relayed by the hub (`send_push`) is switched off by the environment
  # (ENABLE_PUSH_RELAY_SERVER=false), not here.
  module QuietHub
    # Internal::CheckNewVersionsJob reads 'version' from the answer; an empty
    # answer leaves the "new version" notice of the super-admin console unset.
    def sync_with_hub
      {}
    end

    def register_instance(_company_name, _owner_name, _owner_email); end

    def emit_event(_event_name, _event_data); end
  end
end
