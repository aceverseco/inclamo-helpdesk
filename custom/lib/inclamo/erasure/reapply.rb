# frozen_string_literal: true

module Inclamo
  module Erasure
    # After the database is restored from a backup, erases again what the
    # journal says was erased (rake inclamo:erasure:reapply). A backup taken
    # before an erasure brings the erased account back; the journal, kept
    # outside the database, still holds the erasure's line.
    #
    # A store's line names the account it destroyed. That account is erased
    # again when it exists and was created before the erasure was completed:
    # an account made after a restore has a later creation time, whatever id
    # the restored sequence gives it, and is never taken. Safe to run again:
    # a second run finds nothing more to erase.
    class Reapply
      Started = Struct.new(:record, :line, keyword_init: true)

      def initialize(path)
        @path = path
      end

      # The erasures started again, each with its record (`erased`, or
      # `erasing` while background jobs finish it) and its journal line.
      def call
        Journal.read(@path).filter_map do |line|
          store(line) if line['kind'] == 'store'
        end
      end

      private

      # The erasure runs here as far as it can; what Chatwoot leaves to
      # background jobs is finished by Inclamo::StoreErasureJob.
      def store(line)
        account = restored_account(line)
        return unless account

        record = ActiveRecord::Base.transaction { take(line, account) }
        begin
          Store.new(record).run
        rescue Store::NotFinished
          Inclamo::StoreErasureJob.perform_later(record.id)
        end
        Started.new(record: record.reload, line: line)
      end

      def restored_account(line)
        id = Integer(line['account_id'].to_s, 10, exception: false)
        completed_at = Time.iso8601(line['completed_at'].to_s)
        account = id && Account.find_by(id: id)
        account if account && account.created_at <= completed_at
      rescue ArgumentError
        nil
      end

      # The store's row and record as the erasure leaves them at its start
      # (Store.begin!), whatever state the restore brought them back in.
      def take(line, account)
        domain = line['shop_domain'].to_s
        record = Inclamo::ErasureRequest.stores.find_by(account_id: account.id, state: 'erasing') ||
                 Inclamo::ErasureRequest.scheduled_store(domain) ||
                 Inclamo::ErasureRequest.new(kind: 'store', shop_domain: domain, received_at: time(line['received_at']) || Time.current)
        record.update!(state: 'erasing', account_id: account.id, completed_at: nil)
        row = ProvisionedAccount.lock.find_by(account_id: account.id)
        row&.update!(state: 'erasing', account_id: nil, erase_after: nil, storefront_inbox_id: nil, store_access_url: nil)
        record
      end

      def time(text)
        Time.iso8601(text.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
