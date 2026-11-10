# frozen_string_literal: true

module Inclamo
  module Sla
    # Is this message a public reply by a person, the only kind that meets the
    # first-response target? The markers are those Chatwoot v4.19.1 itself uses
    # for a "first reply" (Message#human_response? and #valid_first_reply?):
    #
    # - outgoing and not private;
    # - not a forwarded email (content_attributes.forwarded_message_id);
    # - not sent by an automation rule: every message of a rule carries
    #   content_attributes.automation_rule_id (AutomationRules::ActionService);
    # - not a campaign message (additional_attributes.campaign_id);
    # - sent by a User, or echoed from the channel's own app, where a person
    #   answered (content_attributes.external_echo). Bots send as AgentBot or
    #   Captain::Assistant, rules as nobody.
    #
    # A macro run by an agent sends as that agent, so it counts.
    module HumanReply
      def self.match?(message)
        return false unless message.outgoing? && !message.private?

        content = (message.content_attributes || {}).with_indifferent_access
        additional = (message.additional_attributes || {}).with_indifferent_access
        return false if content[:forwarded_message_id].present?
        return false if content[:automation_rule_id].present?
        return false if additional[:campaign_id].present?

        message.sender.is_a?(User) || content[:external_echo].present?
      end
    end
  end
end
