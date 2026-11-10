# frozen_string_literal: true

module Inclamo
  module Ai
    # The only entry point for AI-requested mutations. Session advisory locks
    # serialize requests without wrapping the remote write in a DB transaction:
    # the runner's attempt journal MUST commit before Shopify is called.
    class OrderAuthority
      class Refused < StandardError; end
      TTL = 15.minutes

      def self.canonical(value)
        case value
        when Hash then value.stringify_keys.sort.to_h.transform_values { |entry| canonical(entry) }
        when Array then value.map { |entry| canonical(entry) }
        else value
        end
      end

      def self.digest(value)
        Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
      end

      def initialize(account:, conversation:, bot: nil, member: nil)
        @account, @conversation, @bot, @member = account, conversation, bot, member
      end

      def context
        connected!
        fresh_reader!
        customer = matched_customer!
        { customer: Shopify::CustomerMatcher.candidate(customer),
          orders: Array(customer.dig('orders', 'nodes')).map { |order| Shopify::OrderPresenter.new(order, shop_domain: @store.shop_domain).as_json },
          policies: ActionPermissions::ACTIONS.map { |action| AiPolicy.for(@account, action).as_json },
          identity_verified: AiIdentityVerification.verified?(@conversation, customer['id'], customer_email: customer.dig('defaultEmailAddress', 'emailAddress')) }
      end

      def propose(input)
        locked do
          connected!
          request = input.stringify_keys.slice('action_name', 'request_id', 'order_id', 'customer_id', 'params', 'address', 'note')
          raise Refused, 'invalid_request' unless request['params'].nil? || request['params'].is_a?(Hash)

          request['params'] ||= {}
          validate_request!(request)
          digest = self.class.digest(request)
          existing = AiProposal.find_by(account_id: @account.id, request_id: request['request_id'])
          if existing
            raise Refused, 'request_id_taken' unless existing.conversation_id == @conversation.id && existing.agent_bot_id == @bot.id && existing.request_digest == digest

            next existing
          end
          policies!(request)
          facts = snapshot(request)
          AiProposal.create!(account: @account, conversation: @conversation, agent_bot: @bot, request_id: request['request_id'],
                             request_digest: digest, action: request['action_name'], expires_at: TTL.from_now,
                             payload: { request: request, summary: facts }.to_json, review_digest: self.class.digest(facts))
        end
      end

      def refresh(proposal)
        locked do
          scoped!(proposal)
          raise Refused, 'already_decided' unless proposal.state == 'proposed' && proposal.action_record.nil?

          request = proposal.data['request']
          policies!(request)
          facts = snapshot(request)
          proposal.update!(payload: { request: request, summary: facts }.to_json, review_digest: self.class.digest(facts), expires_at: TTL.from_now, reason: nil)
          proposal
        end
      end

      def reject(proposal)
        locked do
          scoped!(proposal)
          raise Refused, 'already_decided' unless proposal.state == 'proposed' && proposal.action_record.nil?

          proposal.update!(state: 'rejected', approved_by: @member.user)
          proposal
        end
      end

      def verify_identity(proposal)
        scoped!(proposal)
        raise Refused, 'not_allowed' unless ActionPermissions.current_member(@member)&.administrator?

        fresh_reader!
        customer = matched_customer!
        raise Refused, 'customer_changed' unless customer['id'] == proposal.data.dig('summary', 'customer_id')

        proof = AiIdentityVerification.find_or_initialize_by(account_id: @account.id, contact_inbox_id: @conversation.contact_inbox_id)
        proof.update!(user: @member.user, customer_id: customer['id'], identity_digest: AiIdentityVerification.digest_for(@conversation))
        proposal
      end

      def execute(proposal, digest: nil, autonomous: false)
        locked do
          scoped!(proposal)
          # An existing journal is never reissued here. The common panel's
          # read-only recovery can settle it after a lost Shopify response.
          next proposal if proposal.action_record
          raise Refused, 'already_decided' unless %w[proposed approved].include?(proposal.state)
          raise Refused, 'expired' if proposal.expires_at <= Time.current
          raise Refused, 'review_changed' unless autonomous || digest == proposal.review_digest

          request = proposal.data['request']
          policies!(request, autonomous: autonomous)
          staff_allowed!(request) unless autonomous
          autonomous_ready! if autonomous
          facts = snapshot(request)
          raise Refused, 'review_changed' unless self.class.digest(facts) == proposal.review_digest
          if autonomous
            raise Refused, 'identity_unverified' unless AiIdentityVerification.verified?(@conversation, facts['customer_id'], customer_email: facts['customer_email'])

            bounds!(request, facts)
          end

          proposal.update!(state: 'approved', approved_by: autonomous ? nil : @member.user, reason: nil)
          values = request['params'].deep_dup
          if request['action_name'] == 'edit_items'
            values['expected'] = { 'total_after' => facts.dig('effect', 'total_after', 'amount'), 'balance' => facts.dig('effect', 'balance', 'amount') }
          end
          authorization = lambda do |action, params|
            connected!(proposal)
            raise Refused, 'review_changed' unless @store.id == facts['connection_id'] && @store.shop_domain == facts['shop']
            raise Refused, 'store_unavailable' if @store.unavailable_reason(action)
            policies!(request.merge('action_name' => action, 'params' => params), autonomous: autonomous)
            if autonomous
              autonomous_ready!
              bounds!(request, facts)
              raise Refused, 'identity_unverified' unless AiIdentityVerification.verified?(@conversation, facts['customer_id'], customer_email: facts['customer_email'])
            else
              staff_allowed!(request)
            end
            true
          rescue Refused
            false
          end
          runner = Shopify::OrderActionRunner.new(account: @account, account_user: autonomous ? nil : @member,
                                                  conversation: @conversation, connection: @store, authorizer: authorization, ai_proposal: proposal, matched_customer_id: facts['customer_id'])
          record = runner.perform(action: request['action_name'], action_id: "ai-#{proposal.id}-#{proposal.request_digest.first(24)}",
                                  order_id: request['order_id'], customer_id: request['customer_id'], params: values,
                                  extra: request.slice('address', 'note').symbolize_keys)
          proposal.update!(state: record.outcome, reason: record.refusal)
          proposal
        end
      end

      private

      def locked
        key = Digest::SHA256.hexdigest("inclamo-ai-authority:#{@account.id}").first(15).to_i(16)
        ApplicationRecord.connection_pool.with_connection do |db|
          acquired = db.select_value("SELECT pg_try_advisory_lock(#{key})")
          raise Refused, 'busy' unless acquired

          begin
            yield
          ensure
            db.select_value("SELECT pg_advisory_unlock(#{key})")
          end
        end
      end

      def connected!(proposal = nil)
        @connection = AiConnection.active_for(@account.id)
        @conversation.reload
        expected_bot = @bot&.id || proposal&.agent_bot_id || @proposal&.agent_bot_id
        raise Refused, 'ai_disconnected' unless @connection && @connection.agent_bot_id == expected_bot && @connection.covers?(@conversation.inbox_id)

        @store = ShopifyConnection.find_by(account_id: @account.id)
        raise Refused, 'store_unavailable' unless @store&.working?
      end

      def scoped!(proposal)
        proposal.reload
        raise Refused, 'not_found' unless proposal.account_id == @account.id && proposal.conversation_id == @conversation.id
        raise Refused, 'not_found' if @bot && proposal.agent_bot_id != @bot.id

        @proposal = proposal
        connected!(proposal)
      end

      def validate_request!(request)
        action = request['action_name']
        raise Refused, 'unknown_action' unless ActionPermissions::ACTIONS.include?(action)
        raise Refused, 'invalid_request' unless request['request_id'].to_s.match?(/\A[A-Za-z0-9-]{8,64}\z/) && request.to_json.bytesize <= 65_536

        if OrderAction.order_less?(action)
          raise Refused, 'invalid_request' if request['order_id'].present? || request['customer_id'].present?
        elsif OrderAction.customer_action?(action)
          raise Refused, 'invalid_request' if request['order_id'].present?
        else
          raise Refused, 'invalid_request' if request['customer_id'].present?
        end
        handler = Shopify::OrderActionRunner::HANDLERS.fetch(action)
        allowed = handler::RECORDED - ['expected']
        raise Refused, 'invalid_request' unless (request['params'].keys - allowed).empty?
        raise Refused, 'invalid_request' if request['params'].values.any? { |value| value.is_a?(String) && value.length > 200 }
        raise Refused, 'invalid_request' if request.key?('note') && !%w[order_note customer_note new_order].include?(action)
        raise Refused, 'invalid_request' if request.key?('address') && action != 'address'
        if action == 'address'
          address = request['address']
          raise Refused, 'address_incomplete' unless address.is_a?(Hash) && (address.keys - Shopify::Actions::Address::FIELDS.keys).empty? &&
            Shopify::Actions::Address::REQUIRED.all? { |field| address[field].is_a?(String) && address[field].present? }
        end
        raise Refused, 'invalid_request' if request['note'].to_s.length > 1000
      end

      def policies!(request, autonomous: false)
        action = request['action_name']
        raise Refused, 'unknown_action' unless ActionPermissions::ACTIONS.include?(action)

        ActionPermissions.required(action, request['params']).each do |right|
          policy = AiPolicy.for(@account, right)
          raise Refused, 'policy_forbidden' if policy.mode == 'forbidden'
          raise Refused, 'approval_required' if autonomous && policy.mode != 'autonomous'
          raise Refused, 'invalid_policy' if autonomous && !policy.valid?
        end
      end

      def staff_allowed!(request)
        raise Refused, 'not_allowed' unless ActionPermissions.allows?(@member, request['action_name'], request['params'])
      end

      def autonomous_ready!
        raise Refused, 'ai_unavailable' unless @connection.connected?
        raise Refused, 'human_takeover' unless @conversation.pending? && @conversation.assignee_id.nil? &&
          [nil, @connection.agent_bot_id].include?(@conversation.assignee_agent_bot_id)
        binding = AgentBotInbox.find_by(inbox_id: @conversation.inbox_id, agent_bot_id: @connection.agent_bot_id)
        raise Refused, 'ai_disconnected' unless binding&.active?
      end

      def fresh_reader!
        Shopify::OrderReader.forget!(@account.id)
        @reader = Shopify::OrderReader.new(@store)
      end

      def matched_customer!
        contact = @conversation.contact.reload.dup
        # Widget custom attributes are not an identity proof. AI matching
        # never trusts the remembered customer id used by the staff panel.
        contact.custom_attributes = contact.custom_attributes.to_h.except(Shopify::CustomerMatcher::REMEMBERED)
        match = Shopify::CustomerMatcher.new(@reader, contact, limited: @store.customer_data_limited?).call
        raise Refused, 'customer_unmatched' unless match.state == 'matched'

        @reader.customer_with_orders(match.customer_id) || raise(Refused, 'customer_unmatched')
      end

      def snapshot(request)
        fresh_reader!
        customer = matched_customer!
        action = request['action_name']
        scope_error = @store.unavailable_reason(action)
        raise Refused, scope_error if scope_error

        order = nil
        if OrderAction.customer_action?(action)
          raise Refused, 'not_customers_target' unless request['customer_id'] == customer['id']
        elsif !OrderAction.order_less?(action)
          order = @reader.order(request['order_id']) || raise(Refused, 'unknown_order')
          raise Refused, 'not_customers_target' unless order.dig('customer', 'id') == customer['id']
          refusal = Shopify::OrderPresenter.new(order, shop_domain: @store.shop_domain).refusal(action)
          raise Refused, refusal if refusal
        end
        # Preview authorization is local to this read; it cannot be supplied
        # through a controller parameter and never grants permission to write.
        preview = Shopify::OrderActionRunner.new(account: @account, account_user: nil, conversation: @conversation,
                                                 connection: @store, authorizer: ->(*) { true }, matched_customer_id: customer['id'])
        values = request['params']
        effect = case action
                 when 'new_order' then preview.new_order_preview(params: values)
                 when 'edit_items' then preview.edit_items_preview(order_id: request['order_id'], params: values)
                 when 'refund' then preview.refund_preview(order_id: request['order_id'], params: values)
                 when 'cancel', 'replacement' then preview.step_preview(action: action, order_id: request['order_id'], params: values)
                 when 'discount'
                   DiscountPreset.find_by(account_id: @account.id, id: values['preset_id'])&.as_json || raise(Refused, 'unknown_preset')
                 else {}
                 end.deep_stringify_keys
        raise Refused, effect['refusal'] if effect['refusal']
        raise Refused, 'refund_amount_unknown' if action == 'cancel' && effect['refund'] == 'unknown'
        if action == 'refund' && values['mode'] == 'items'
          lines = order.dig('lineItems', 'nodes').index_by { |line| line['id'] }
          effect['items'] = Array(values['items']).map do |wanted|
            line = lines.fetch(wanted['line_item_id'])
            { 'title' => line['title'], 'variant' => line['variantTitle'], 'quantity' => wanted['quantity'].to_i }
          end
        end

        {
          'customer_id' => customer['id'], 'customer_email' => customer.dig('defaultEmailAddress', 'emailAddress'),
          'order_number' => order&.dig('name'), 'effect' => effect,
          'order_total' => order&.dig('currentTotalPriceSet', 'shopMoney'), 'state' => order&.dig('displayFulfillmentStatus'),
          'shop' => @store.shop_domain, 'connection_id' => @store.id,
          'source_digest' => self.class.digest([order, customer.except('orders'),
                                               (OrderAction.customer_action?(action) ? @reader.customer_marks(customer['id']) : nil)])
        }
      rescue Shopify::Actions::Refused => e
        raise Refused, e.code
      end

      def bounds!(request, facts)
        ActionPermissions.required(request['action_name'], request['params']).each do |right|
          policy = AiPolicy.for(@account, right)
          limits = policy.limits
          if AiPolicy::ORDER_ACTIONS.include?(right) && facts['state']
            raise Refused, 'state_limit' unless limits['allowed_states'].include?(facts['state'])
          end
          amounts = []
          amounts << facts['order_total'] if facts['order_total'] && right != 'discount'
          effect = facts['effect']
          amounts << effect['total'] if effect['total'].is_a?(Hash) && right != 'discount'
          amounts << effect['total_after'] if effect['total_after'].is_a?(Hash) && right != 'discount'
          amounts << effect.slice('amount', 'currency') if %w[refund cancel].include?(request['action_name']) && effect['amount']
          if right == 'discount'
            discount = request['action_name'] == 'discount' ? effect : request.dig('params', 'discount')
            kind = discount['kind'] || discount['type']
            if kind == 'percentage'
              raise Refused, 'percentage_limit' if discount['value'].to_d > limits['max_percentage'].to_d
            else
              amounts << { 'amount' => discount['value'], 'currency' => @store.shop_currency }
            end
          end
          amounts.each do |money|
            raise Refused, 'currency_limit' unless (money['currency'] || money['currencyCode']) == limits['currency']
            raise Refused, 'amount_limit' if money['amount'].blank? || money['amount'].to_d > limits['max_amount'].to_d
          end
          if AiPolicy::ORDER_ACTIONS.include?(right) && facts['order_total'].nil? && request['action_name'] != 'new_order'
            raise Refused, 'amount_unavailable'
          end
        end
      end
    end
  end
end
