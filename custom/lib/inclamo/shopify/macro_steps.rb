# frozen_string_literal: true

module Inclamo
  module Shopify
    # The order steps a macro can contain. Each is one order action with fixed
    # parameters, on the order tied to the conversation, performed by the same
    # runner as the panel's dialogs and as the person who runs the macro: the
    # same role, scopes, record and private note. See the capability
    # macro-order-actions.
    #
    # Wired into Chatwoot by custom/config/overlay.rb: Validation is prepended
    # to Macro, Execution to Macros::ExecutionService. Automation rules are
    # left alone, so Chatwoot's own validation refuses order steps there.
    module MacroSteps
      # step name => [order action, its parameters]
      STEPS = {
        # The whole refundable amount; nothing goes back in stock; the store tells the customer.
        'inclamo_refund_full' => ['refund', { 'mode' => 'full', 'restock' => false, 'notify' => true }.freeze],
        # The shipping alone, the items are not refunded; the store tells the customer.
        'inclamo_refund_shipping' => ['refund', { 'mode' => 'shipping', 'restock' => false, 'notify' => true }.freeze],
        # Cancelled at the customer's request with a full refund, the items back in stock; the store tells the customer.
        'inclamo_cancel_order' => ['cancel', { 'reason' => 'CUSTOMER', 'refund' => true, 'restock' => true, 'notify' => true }.freeze],
        # A new order with the same items to the same address, at no charge.
        'inclamo_replacement' => ['replacement', { 'items' => [] }.freeze]
      }.freeze

      def self.step?(name)
        STEPS.key?(name.to_s)
      end

      # The order steps of a macro in its order, as [position, name] pairs.
      def self.of(macro)
        Array(macro.actions).each_with_index.filter_map do |action, index|
          name = action.to_h.stringify_keys['action_name']
          [index, name] if step?(name)
        end
      end

      # Lets the four step names pass a macro's validation.
      module Validation
        private

        def json_actions_format
          return if actions.blank?

          unsupported = actions.map { |action, _| action['action_name'] } - ::Macro::ACTIONS_ATTRS - STEPS.keys
          errors.add(:actions, "Macro execution actions #{unsupported.join(',')} not supported.") if unsupported.any?
        end
      end

      # Chatwoot runs every step of a macro and swallows its errors. An order
      # step that is not done stops the macro instead: a message saying "we
      # refunded you" never follows a refund that did not happen. The steps
      # before it stay done, and Chatwoot's own steps keep their behaviour.
      module Execution
        STOP = :inclamo_macro_stopped

        def perform
          catch(STOP) { super }
        end

        STEPS.each_key do |name|
          define_method(name) { |_params| run_order_step(name) }
          private name
        end

        private

        # Chatwoot's loop would swallow an exception, so the stop is a throw.
        def run_order_step(name)
          done = Step.new(name, macro: @macro, conversation: @conversation.reload, user: @user).perform
          throw STOP unless done
        end
      end

      # One order step in one run of a macro. `perform` is true when the store
      # did it. Otherwise the conversation gets a private note naming the step
      # and the reason, and `perform` is false.
      class Step
        def initialize(name, macro:, conversation:, user:)
          @name = name.to_s
          @macro = macro
          @conversation = conversation
          @user = user
          @account = macro.account
        end

        def perform
          order_id = @conversation.custom_attributes.to_h[ConversationOrder::ID_KEY]
          return stopped('no_order') if order_id.blank?

          action, params = STEPS.fetch(@name)
          record = runner.perform(action: action, action_id: "macro-#{SecureRandom.hex(12)}", order_id: order_id, params: params, macro_id: @macro.id)
          return true if record.outcome == 'accepted'

          @action = action
          record.outcome == 'refused' ? stopped(record.refusal, record.store_message) : stopped(record.outcome)
        rescue StandardError => e
          ChatwootExceptionTracker.new(e, account: @account).capture_exception
          stopped('failed')
        end

        private

        def runner
          OrderActionRunner.new(account: @account, account_user: @account.account_users.find_by(user_id: @user.id), conversation: @conversation)
        end

        def stopped(reason, message = nil)
          content = I18n.t('inclamo.macro_steps.stopped', macro: @macro.name, step: I18n.t("inclamo.macro_steps.names.#{@name}"),
                                                          reason: explain(reason, message))
          Messages::MessageBuilder.new(@user, @conversation, { content: content, private: true }).perform
          false
        end

        def explain(reason, message)
          key = "inclamo.macro_steps.reasons.#{reason}"
          return I18n.t(key, message: message, scopes: missing_scopes.join(', ')) if I18n.exists?(key)

          message.presence || I18n.t('inclamo.macro_steps.reasons.other', code: reason)
        end

        def missing_scopes
          connection = ShopifyConnection.find_by(account_id: @account.id)
          connection && @action ? connection.missing_scopes_for(@action) : []
        end
      end

      # What the order steps of a macro would do in a conversation, for the
      # confirmation before it runs, computed by the code the steps run with.
      # Changes nothing. With no order tied to the conversation the store is
      # not asked anything.
      class Preview
        def initialize(macro:, conversation:, account_user:)
          @macro = macro
          @conversation = conversation
          @account_user = account_user
        end

        def as_json(*)
          attributes = @conversation.custom_attributes.to_h
          order_id = attributes[ConversationOrder::ID_KEY]
          steps = MacroSteps.of(@macro)
          return { order: nil, steps: steps.map { |position, name| { position: position, step: name } } } if order_id.blank?

          runner = OrderActionRunner.new(account: @macro.account, account_user: @account_user, conversation: @conversation)
          {
            order: { id: order_id, number: attributes['shopify_order_number'] },
            steps: steps.map do |position, name|
              action, params = STEPS.fetch(name)
              { position: position, step: name }.merge(runner.step_preview(action: action, order_id: order_id, params: params))
            end
          }
        end
      end
    end
  end
end
