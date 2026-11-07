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
    # to Macro, Execution to Macros::ExecutionService, Job to
    # MacrosExecutionJob and ExecutionGuard to the macros controller.
    # Automation rules are left alone, so Chatwoot's own validation refuses
    # order steps there.
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
      RUN = :inclamo_macro_run

      def self.step?(name)
        STEPS.key?(name.to_s)
      end

      def self.name_of(action)
        action.respond_to?(:[]) ? (action['action_name'] || action[:action_name]).to_s : ''
      end

      # The order steps of a macro in its order, as [position, name] pairs.
      def self.of(macro)
        Array(macro.actions).each_with_index.filter_map do |action, index|
          name = name_of(action)
          [index, name] if step?(name)
        end
      end

      # The macro's steps as they are now, as a short fingerprint: what an
      # agent confirmed is what runs.
      def self.digest(macro)
        Digest::SHA256.hexdigest(Array(macro.actions).to_json)
      end

      # The job that runs a macro, while it runs: a job that runs again
      # (Sidekiq hands an unfinished job back after a restart) is the same run.
      def self.within_run(id)
        before = Thread.current[RUN]
        Thread.current[RUN] = id
        yield
      ensure
        Thread.current[RUN] = before
      end

      def self.current_run
        Thread.current[RUN]
      end

      # Lets the four step names pass a macro's validation. Chatwoot's own
      # check runs on the other steps, whatever it checks in a later release.
      module Validation
        private

        def json_actions_format
          return super if MacroSteps.of(self).empty?

          others = dup
          others.actions = Array(actions).reject { |action| MacroSteps.step?(MacroSteps.name_of(action)) }
          others.send(:json_actions_format)
          others.errors.each { |error| errors.add(error.attribute, error.message) }
        end
      end

      # Gives the steps of a macro the id of the job that runs it.
      module Job
        def perform(*args, **options, &block)
          MacroSteps.within_run(job_id) { super(*args, **options, &block) }
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

        # Chatwoot's loop would swallow an exception, so the stop is a throw,
        # thrown unless the step says it was done: also when the step itself
        # failed, even while writing its note.
        def run_order_step(name)
          done = begin
            Step.new(name, macro: @macro, conversation: @conversation.reload, user: @user, action_id: step_action_id(name)).perform
          rescue StandardError => e
            ChatwootExceptionTracker.new(e, account: @macro.account).capture_exception
            false
          end
          throw STOP unless done == true
        end

        # The same for a step in every run of one job, so a job that runs
        # again continues the step's attempt instead of acting a second time.
        # Outside a job, unique to this run.
        def step_action_id(name)
          @inclamo_run ||= MacroSteps.current_run || SecureRandom.uuid
          @inclamo_seen ||= Hash.new(0)
          @inclamo_seen[name] += 1
          "macro-#{Digest::SHA256.hexdigest([@inclamo_run, @macro.id, @conversation.id, name, @inclamo_seen[name]].join(':')).first(40)}"
        end
      end

      # One order step in one run of a macro. `perform` is true when the store
      # did it. Otherwise the conversation gets a private note naming the step
      # and the reason, and `perform` is false.
      class Step
        def initialize(name, macro:, conversation:, user:, action_id: nil)
          @name = name.to_s
          @macro = macro
          @conversation = conversation
          @user = user
          @account = macro.account
          @action, @params = STEPS.fetch(@name)
          @action_id = action_id || "macro-#{SecureRandom.hex(12)}"
        end

        def perform
          order_id = ConversationOrder.new(@conversation, connection: connection).marked_id
          return stopped('no_order') if order_id.blank?

          record = runner.perform(action: @action, action_id: @action_id, order_id: order_id, params: @params, macro_id: @macro.id)
          return true if record.outcome == 'accepted'

          record.outcome == 'refused' ? stopped(record.refusal, record.store_message) : stopped(record.outcome)
        rescue StandardError => e
          ChatwootExceptionTracker.new(e, account: @account).capture_exception
          stopped_after_error
        end

        private

        def connection
          return @connection if defined?(@connection)

          @connection = ShopifyConnection.find_by(account_id: @account.id)
        end

        def runner
          OrderActionRunner.new(account: @account, account_user: @account.account_users.find_by(user_id: @user.id), conversation: @conversation,
                                connection: connection)
        end

        # The store may have acted before the error: the record of the attempt
        # says how far it got.
        def stopped_after_error
          record = OrderAction.find_by(account_id: @account.id, action_id: @action_id)
          case record&.outcome
          when nil then stopped('failed')
          when 'accepted' then stopped('failed_after_done')
          when 'refused' then stopped(record.refusal, record.store_message)
          else stopped('unknown')
          end
        end

        def stopped(reason, message = nil)
          content = I18n.t('inclamo.macro_steps.stopped', macro: @macro.name, step: I18n.t("inclamo.macro_steps.names.#{@name}"),
                                                          reason: explain(reason, message))
          Messages::MessageBuilder.new(@user, @conversation, { content: content, private: true }).perform
          false
        end

        def explain(reason, message)
          key = "inclamo.macro_steps.reasons.#{reason}"
          return message.presence || I18n.t('inclamo.macro_steps.reasons.other', code: reason) unless I18n.exists?(key)

          scopes = reason == 'missing_scope' && connection ? connection.missing_scopes_for(@action) : []
          I18n.t(key, message: message, scopes: scopes.join(', '))
        end
      end

      # What the order steps of a macro would do in a conversation, for the
      # confirmation before it runs, computed by the code the steps run with.
      # Changes nothing. With no order tied to the conversation the store is
      # not asked anything. `digest` names the macro as it was shown.
      class Preview
        def initialize(macro:, conversation:, account_user:)
          @macro = macro
          @conversation = conversation
          @account_user = account_user
        end

        def as_json(*)
          connection = ShopifyConnection.find_by(account_id: @macro.account_id)
          tie = ConversationOrder.new(@conversation, connection: connection)
          steps = MacroSteps.of(@macro)
          shown = { digest: MacroSteps.digest(@macro) }
          return shown.merge(order: nil, steps: steps.map { |position, name| { position: position, step: name } }) if tie.marked_id.blank?

          shown.merge(order: { id: tie.marked_id, number: tie.marked_number }, steps: previews(steps, tie.marked_id, connection))
        end

        private

        def previews(steps, order_id, connection)
          return [] if steps.empty?

          runner = OrderActionRunner.new(account: @macro.account, account_user: @account_user, conversation: @conversation, connection: connection)
          sequence = Sequence.new
          steps.map do |position, name|
            action, params = STEPS.fetch(name)
            { position: position, step: name }.merge(sequence.next(name) { runner.step_preview(action: action, order_id: order_id, params: params) })
          end
        end
      end

      # What the order steps before a step will have done to the order by the
      # time it runs. The store is asked about the order as it is now; the
      # refunds of the steps before are taken off, and a step after one that
      # stops the macro does not run.
      class Sequence
        def initialize
          @refunded = BigDecimal('0')
          @all_refunded = false
          @shipping_refunded = false
          @cancelled = false
          @stopped = false
        end

        # The step's preview of the order as it is now comes from the block.
        def next(name)
          return { after_stop: true } if @stopped

          preview = yield
          preview = after_the_steps_before(name, preview) unless preview[:refusal]
          @stopped = true if preview[:refusal]
          preview
        end

        private

        def after_the_steps_before(name, preview)
          case name
          when 'inclamo_refund_full' then full_refund(preview)
          when 'inclamo_refund_shipping' then shipping_refund(preview)
          when 'inclamo_cancel_order' then cancellation(preview)
          else preview
          end
        end

        def full_refund(preview)
          left = @all_refunded ? 0 : preview[:amount].to_d - @refunded
          return { refusal: 'nothing_to_refund', message: nil } unless left.positive?

          @all_refunded = @shipping_refunded = true
          preview.merge(amount: left.to_s('F'))
        end

        def shipping_refund(preview)
          return { refusal: 'no_shipping_to_refund', message: nil } if @all_refunded || @shipping_refunded

          @shipping_refunded = true
          @refunded += preview[:amount].to_d
          preview
        end

        # A cancellation refunds whatever remains, and only once.
        def cancellation(preview)
          return { refusal: 'already_cancelled', message: nil } if @cancelled

          @cancelled = true
          refunded_before = @all_refunded
          @all_refunded = @shipping_refunded = true
          return preview unless preview[:amount]

          left = refunded_before ? 0 : preview[:amount].to_d - @refunded
          left.positive? ? preview.merge(amount: left.to_s('F')) : preview.except(:amount, :currency).merge(refund: 'none_left')
        end
      end

      # The agent's confirmation of a macro with order steps, given in the
      # dashboard's dialog and kept a short while for the run that follows
      # it. It holds for that macro as the agent saw it, in that conversation,
      # for one run.
      class Confirmation
        KEPT = 5.minutes

        def initialize(macro:, conversation:, user:)
          @macro = macro
          @conversation = conversation
          @user = user
        end

        # False when the macro changed since the agent saw it.
        def give!(digest)
          return false unless ActiveSupport::SecurityUtils.secure_compare(digest.to_s, MacroSteps.digest(@macro))

          ::Redis::Alfred.set(key, digest, ex: KEPT.to_i)
          true
        end

        # Takes the confirmation for one run: true when there was one for the
        # macro as it is now.
        def take!
          given, = ::Redis::Alfred.with do |redis|
            redis.multi do |transaction|
              transaction.get(key)
              transaction.del(key)
            end
          end
          given.present? && ActiveSupport::SecurityUtils.secure_compare(given, MacroSteps.digest(@macro))
        end

        private

        def key
          "inclamo:macro_confirmation:#{@macro.account_id}:#{@user.id}:#{@macro.id}:#{@conversation.id}"
        end
      end

      # Chatwoot's request that runs a macro. From the dashboard, a macro with
      # order steps runs only after the agent confirmed it, in one
      # conversation: a page holding an older copy of the macro, without its
      # order steps, shows no dialog, and nothing of the macro runs. A run
      # through the API with an access token has no dialog (design D6), and
      # each step is checked when it runs.
      module ExecutionGuard
        def execute
          refusal = inclamo_unconfirmed
          return super unless refusal

          render json: { error: refusal, message: I18n.t("inclamo.macro_steps.unconfirmed.#{refusal}") }, status: :unprocessable_entity
        end

        private

        def inclamo_unconfirmed
          return if @macro.nil? || authenticate_by_access_token? || MacroSteps.of(@macro).empty?

          ids = Array(params[:conversation_ids])
          return 'one_at_a_time' unless ids.size == 1

          conversation = Current.account.conversations.find_by(display_id: ids.first)
          'not_confirmed' unless conversation && Confirmation.new(macro: @macro, conversation: conversation, user: Current.user).take!
        end
      end
    end
  end
end
