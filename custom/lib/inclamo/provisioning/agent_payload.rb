# frozen_string_literal: true

module Inclamo
  module Provisioning
    # The body of "the store's account is connected to the agent"
    # (docs/app-agent-connection.md §3.1): the contract version, the AI
    # service's address and a one-time pairing token. It is read and checked
    # before anything is looked up or created, and an address the operator did
    # not allow stops here, before any request leaves the helpdesk. A body that
    # does not read raises Payload::Invalid with the contract's error code.
    #
    # The body names no inboxes; an `inbox_ids` sent anyway is ignored like any
    # other unknown field.
    class AgentPayload
      MAX_TOKEN = 4096

      # An Inclamo::Ai::Pairing.
      attr_reader :pairing

      def initialize(raw_body)
        body = parse(raw_body)
        invalid!('contract_unsupported', "contract must be #{CONTRACT}") unless body['contract'] == CONTRACT

        address = body['service_url'].is_a?(String) ? AgentServices.normalize(body['service_url']) : nil
        invalid!('service_url_invalid', 'service_url is not an absolute HTTPS address') unless address
        invalid!('service_url_not_allowed', 'service_url is not an address the operator allowed') unless AgentServices.allowed?(address)

        token = body['token']
        invalid!('token_invalid', 'token is absent, empty or too long') unless token.is_a?(String) && token.present? && token.length <= MAX_TOKEN

        @pairing = Ai::Pairing.new(service_url: address, token: token)
      end

      private

      # A body that is not a JSON object states no contract version at all.
      def parse(raw_body)
        body = JSON.parse(raw_body.to_s)
        body.is_a?(Hash) ? body : invalid!('contract_unsupported', 'the body is not a JSON object')
      rescue JSON::ParserError
        invalid!('contract_unsupported', 'the body is not a JSON object')
      end

      def invalid!(code, message)
        raise Payload::Invalid.new(code, message)
      end
    end
  end
end
