# frozen_string_literal: true

module Inclamo
  module Erasure
    # The destruction of a store's account whose erasure has come due
    # (docs/app-store-erasure.md §3.4). Everything in the account goes: its
    # conversations, messages and files, contacts, inboxes, labels, settings,
    # the store connection with its key and the AI agent's connection, and
    # every user who belonged to this account only. The store's row keeps
    # only its domain, the fact and the time.
    #
    # Store.begin! moves a due store to `erasing`; the destruction itself runs
    # in Inclamo::StoreErasureJob, which calls #run until it is complete:
    #   1. the AI agent is disconnected if it is still connected (the AI
    #      service is told; not reaching it stops nothing), and a key to the
    #      store from the store app is deleted with the store's cached answers
    #      (Shopify::AppConnection.forget_key!);
    #   2. the users who belong to this account only are chosen, once;
    #   3. the rows that hold the account back, or that nothing of Chatwoot
    #      removes with it, are deleted, and so are the account's memberships;
    #   4. Chatwoot's own deletion of an account runs (DeleteObjectJob, which
    #      leaves part of the work to background jobs);
    #   then, once no table names the account any longer:
    #   5. the chosen users are destroyed, unless they have joined another
    #      account meanwhile;
    #   6. once no table names them either, the store's row turns `erased`, the
    #      record is completed and journaled, the store's open requests about
    #      shoppers are done by the store's erasure, and the account's counter
    #      of cached store answers goes from Redis.
    # Until then #run raises NotFinished, and the job tries again later.
    class Store
      class NotFinished < StandardError; end

      def initialize(record, client: Ai::ServiceClient.new)
        @record = record
        @client = client
      end

      # A store whose erasure has come due is taken under its row's lock: its
      # account must be suspended still, and its time passed. Its row then
      # names no account, and the record names the account to destroy.
      # Answers the record, or nil when the store is not taken. An account
      # that was made active by other means than the app (by the operator) has
      # its erasure withdrawn: an active account is never erased this way.
      def self.begin!(row, now: Time.current)
        row.with_lock do
          next unless row.suspended? && row.erase_after && row.erase_after <= now

          account = row.account
          next withdraw!(row, now) unless account&.suspended?

          record = Inclamo::ErasureRequest.scheduled_store(row.shop_domain) ||
                   Inclamo::ErasureRequest.new(kind: 'store', shop_domain: row.shop_domain, received_at: now)
          record.update!(state: 'erasing', account_id: account.id)
          row.update!(state: 'erasing', account_id: nil, erase_after: nil, storefront_inbox_id: nil, store_access_url: nil)
          record
        end
      end

      def self.withdraw!(row, now)
        Erasure.cancel!(row, now: now)
        ProvisioningEvent.record(outcome: 'erasure_cancelled', shop_domain: row.shop_domain, request_id: nil)
        nil
      end

      def run
        account = Account.find_by(id: @record.account_id)
        start(account) if account
        delete_unreached(@record.account_id)
        not_finished!('account', Leftovers.account(@record.account_id))
        destroy_users
        not_finished!('users', Leftovers.users(@record.user_ids))
        complete
      end

      private

      # Steps 1 to 4. Run again on a later attempt as long as the account is there.
      def start(account)
        Provisioning::AgentConnection.disconnect_for_suspension(account, @client) if Inclamo::AiConnection.active_for(account.id)
        Shopify::AppConnection.forget_key!(account)
        @record.update!(user_ids: sole_user_ids(account)) if @record.user_ids.nil?
        delete_unreached(account.id)
        delete_memberships(account.id)
        DeleteObjectJob.perform_now(account)
      end

      # Users whose only account this is. The installation's super admins are
      # the operator's and are never chosen.
      def sole_user_ids(account)
        members = AccountUser.where(account_id: account.id).select(:user_id)
        elsewhere = AccountUser.where.not(account_id: account.id).select(:user_id)
        User.where(id: members).where.not(id: elsewhere).where("users.type IS DISTINCT FROM 'SuperAdmin'").order(:id).pluck(:id)
      end

      # The account's memberships go in one statement, before the account: each
      # one destroyed after it would start Chatwoot's job for a person leaving
      # an account (Agents::DestroyJob), which fails once the account is gone.
      # What a membership holds goes with it in the database (the overlay's
      # tables of a membership delete their rows with it), and the account's
      # inboxes, teams, settings and conversations go with the account.
      def delete_memberships(account_id)
        AccountUser.where(account_id: account_id).delete_all
      end

      def delete_unreached(account_id)
        connection = ActiveRecord::Base.connection
        (References.holding_account + References::CHATWOOT_UNREACHED).each do |table|
          connection.exec_delete("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{connection.quote(Integer(account_id))}")
        end
      end

      # Step 5. A user who joined another account since being chosen (the store
      # installed the app again while its old account was being destroyed) is
      # kept, and no longer counted among the erased.
      def destroy_users
        ids = Array(@record.user_ids)
        kept = AccountUser.where(user_id: ids).distinct.pluck(:user_id)
        @record.update!(user_ids: ids - kept) if kept.any?
        User.where(id: @record.user_ids).find_each do |user|
          Inclamo::AiIdentityVerification.where(user_id: user.id).delete_all
          user.destroy!
        end
      end

      # Step 6, once: a second attempt finds the record completed.
      def complete
        completed = @record.with_lock do
          next false unless @record.state == 'erasing'

          now = Time.current
          row = ProvisionedAccount.lock.find_by(shop_domain: @record.shop_domain)
          row.update!(state: 'erased', erased_at: now) if row&.erasing?
          @record.update!(state: 'erased', completed_at: now)
          finish_shopper_requests(now)
          journal!
          true
        end
        return unless completed

        ::Redis::Alfred.delete(Shopify::OrderReader.generation_key(@record.account_id))
        ProvisioningEvent.record(outcome: 'erased', shop_domain: @record.shop_domain, request_id: nil)
      end

      # The store's requests about shoppers go with its account, held ones too:
      # they are done, and nothing of the shopper stays readable.
      def finish_shopper_requests(now)
        Inclamo::ErasureRequest.shoppers.where(shop_domain: @record.shop_domain, account_id: @record.account_id)
                               .where.not(state: 'done').find_each do |request|
          request.update!(state: 'done', done_by: 'store_erasure', completed_at: now, email: nil, phone: nil, hold_reason: nil)
        end
      end

      # Written before the completion commits: a journal line for an erasure
      # that then failed to commit is applied again harmlessly; a completion
      # without its line could not be applied again after a restore.
      def journal!
        Journal.append(Journal.store_entry(@record))
      rescue Journal::Unwritable => e
        raise NotFinished, e.message
      end

      def not_finished!(what, tables)
        return if tables.empty?

        raise NotFinished, "the erasure of #{@record.shop_domain} (record #{@record.id}) is not finished: " \
                           "rows of #{tables.join(', ')} still name its #{what}"
      end
    end
  end
end
