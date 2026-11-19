# frozen_string_literal: true

module Inclamo
  module Provisioning
    # Starts an ordinary helpdesk session for the user an entry address was
    # made for, with Chatwoot's own pieces, in the order its sign-in with a
    # one-time link takes them (DeviseOverrides::SessionsController):
    #   - the installation's limit of sessions per user (MAX_USER_SESSIONS),
    #     applied by Chatwoot's own routines. A sign-in from a browser at the
    #     limit is shown a list of sessions to end; there is no such page on
    #     this way in, so the oldest session gives way, as Chatwoot does for a
    #     client that cannot show the list;
    #   - a devise-token-auth token of the usual lifespan, saved on the user;
    #   - the session row Chatwoot lists in the user's profile.
    # The caller signs the user in for the request (Devise's trackable fields)
    # and hands the browser the session (SESSION_COOKIE).
    module EntrySession
      # Where Chatwoot's dashboard keeps its session: the five headers of a
      # sign-in, as JSON, in a cookie the dashboard's script reads
      # (app/javascript/dashboard/store/utils/api.js, setAuthCredentials).
      SESSION_COOKIE = 'cw_d_session_info'
      HEADERS = %w[access-token token-type client expiry uid].freeze

      module_function

      # The headers of the new session, keyed by their lower-case names.
      def start(user, request)
        make_room(user)
        token = user.create_token
        user.save!
        track(user, request, token.client)
        user.build_auth_headers(token.token, token.client).transform_keys { |name| name.to_s.downcase }.slice(*HEADERS)
      end

      # The cookie's value, as the dashboard writes it after a sign-in.
      def cookie(headers, request)
        { value: headers.to_json, expires: Time.zone.at(headers.fetch('expiry').to_i), path: '/', same_site: :lax,
          secure: request.ssl?, httponly: false }
      end

      def make_room(user)
        limiter = DeviseOverrides::SessionsController.new
        limiter.send(:evict_oldest_session, user) if limiter.send(:sessions_limit_reached?, user)
      end

      # As Chatwoot does after a sign-in: a failure to record the session does
      # not undo it.
      def track(user, request, client_id)
        UserSessionTrackingService.new(user: user, request: request, client_id: client_id).create_or_update!
      rescue StandardError => e
        Rails.logger.warn("[inclamo entry] session not tracked: #{e.class}")
      end
    end
  end
end
