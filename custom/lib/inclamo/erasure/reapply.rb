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
    #
    # A shopper's line names the account and holds the shopper's keyed
    # digests. In that account, if it exists and was created before the
    # erasure was completed, every contact made before the completion whose
    # email or phone has one of those digests is deleted again with what the
    # overlay keeps about it and about the line's orders (ShopperDeletion), and
    # the line's ticket, when the restore brought it back unfinished, is
    # finished as it was (ShopperFinish). A request the restore brought back
    # held or waiting that the journal does not name stays as it is: its clock
    # is its own.
    class Reapply
      # `erased`: for a shopper's line, the contacts deleted again.
      Started = Struct.new(:record, :line, :erased, keyword_init: true)

      def initialize(path)
        @path = path
      end

      # The erasures started again, each with its record (`erased`, or
      # `erasing` while background jobs finish it; a shopper's ticket, if the
      # restore brought it back) and its journal line.
      def call
        Journal.read(@path).filter_map do |line|
          case line['kind']
          when 'store' then store(line)
          when 'shopper' then shopper(line)
          end
        end
      end

      private

      def shopper(line)
        account = restored_account(line)
        return unless account

        completed_at = time(line['completed_at'])
        Ticket.acting(account) do
          ActiveRecord::Base.transaction do
            contacts = digested(account, completed_at, line['email_digest'], line['phone_digest'])
            erased = ShopperDeletion.new(account, contacts, Array(line['order_ids'])).call
            record = finish_restored(line, account, completed_at)
            Started.new(record: record, line: line, erased: erased) if erased.positive? || record
          end
        end
      end

      # The account's contacts, made before the erasure was completed, whose
      # email or phone has one of the digests.
      def digested(account, completed_at, email_digest, phone_digest)
        return [] if email_digest.blank? && phone_digest.blank?

        Contact.where(account_id: account.id).where(created_at: ..completed_at).find_each.select do |contact|
          (email_digest.present? && Shoppers.digest(Shoppers.email(contact.email)) == email_digest) ||
            (phone_digest.present? && Shoppers.digest(Shoppers.digits(contact.phone_number)) == phone_digest)
        end
      end

      def finish_restored(line, account, completed_at)
        id = Integer(line['request_id'].to_s, 10, exception: false)
        request = id && Inclamo::ErasureRequest.lock.find_by(id: id, kind: 'shopper_erasure', account_id: account.id)
        return unless request && !request.done?

        by = line['done_by'] == 'team' ? User.find_by(id: line['done_by_id']) : nil
        ShopperFinish.new(request, by: by, now: completed_at, done_by: line['done_by'] == 'team' ? 'team' : 'automatic',
                                   journal: false).call
      end

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
