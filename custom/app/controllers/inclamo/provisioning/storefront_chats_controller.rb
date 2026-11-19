# frozen_string_literal: true

# The two calls of the store app about a store's storefront chat
# (docs/app-storefront-chat.md). They are opened by the same signature, answer
# a request id once and are recorded as the store app's other calls, which is
# what this controller takes from the one it extends.
class Inclamo::Provisioning::StorefrontChatsController < Inclamo::Provisioning::StoresController
  # PUT: the store has its storefront inbox. Find it, or create it.
  def update
    payload = Inclamo::Provisioning::StorefrontChatPayload.new(request.raw_post)
    result = Inclamo::Provisioning::StorefrontChat.new(@verdict.shop_domain, website_url: payload.storefront_url).call
    record("chat_#{result.outcome}")
    render json: chat_body(result).merge(outcome: result.outcome), status: result.outcome == 'created' ? :created : :ok
  rescue Inclamo::Provisioning::Payload::Invalid => e
    record('chat_refused')
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  rescue Inclamo::Provisioning::StorefrontChat::Refused => e
    record('chat_refused')
    render json: { error: e.code }, status: e.status
  end

  # GET: what is there. Only the public values: never the inbox's
  # identity-verification key, its settings, conversations, contacts or members.
  def show
    render json: chat_body(Inclamo::Provisioning::StorefrontChat.find(@verdict.shop_domain))
  rescue Inclamo::Provisioning::StorefrontChat::Refused => e
    render json: { error: e.code }, status: e.status
  end

  private

  def chat_body(result)
    {
      contract: Inclamo::Provisioning::CONTRACT,
      inbox_id: result.inbox.id,
      website_token: result.inbox.channel.website_token,
      widget_base_url: Inclamo::Provisioning.helpdesk_url,
      state: result.row.suspended? || result.row.account.suspended? ? 'suspended' : 'active'
    }
  end
end
