# frozen_string_literal: true

module Inclamo
  module Shopify
    # Client credentials grant: trades the client ID and secret of a merchant's
    # own Dev Dashboard app for an Admin API token that lives 24 hours. Works
    # only for a store on which that app is installed.
    class TokenExchange
      Result = Struct.new(:access_token, :expires_at, keyword_init: true)
      TIME_LIMIT = 10

      def self.call(domain:, client_id:, client_secret:)
        raise Error::InvalidDomain, 'not a myshopify.com domain' unless Shopify.valid_domain?(domain)

        uri = URI.join(Shopify.base_url(domain), '/admin/oauth/access_token')
        body = URI.encode_www_form(grant_type: 'client_credentials', client_id: client_id, client_secret: client_secret)
        headers = { 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json', 'X-Shopify-Shop-Domain' => domain }
        result_of(Http.post(uri, headers: headers, body: body, time_limit: TIME_LIMIT))
      end

      def self.result_of(response)
        case response.code.to_i
        when 200
          payload = JSON.parse(response.body.to_s)
          Result.new(access_token: payload.fetch('access_token'), expires_at: Time.current + payload.fetch('expires_in').to_i)
        when 400, 401, 403 then raise refusal_for(response)
        when 402, 404, 423 then raise Error::ShopUnavailable, "the store answered #{response.code}"
        else raise Error::Unavailable, "the store answered #{response.code}"
        end
      rescue JSON::ParserError, KeyError
        raise Error::Unavailable, 'the store sent a token answer that could not be read'
      end
      private_class_method :result_of

      # Shopify answers a refused exchange with a page whose only machine-readable
      # part is its title, e.g. "400 - Oauth error app_not_installed".
      def self.refusal_for(response)
        reason = response.body.to_s[/Oauth error ([a-z_]+)/, 1] || response.body.to_s[/"error"\s*:\s*"([a-z_]+)"/, 1]
        return Error::AppNotInstalled.new('the app is not installed on this store') if reason == 'app_not_installed'

        Error::CredentialsRefused.new("the store refused the client ID or secret (#{reason || response.code})")
      end
      private_class_method :refusal_for
    end
  end
end
