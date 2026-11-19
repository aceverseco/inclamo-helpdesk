# frozen_string_literal: true

namespace :inclamo do
  namespace :erasure do
    desc 'After a restore from backup, erase again what the erasure journal says was erased: ' \
         'inclamo:erasure:reapply[journal_path] (default: INCLAMO_ERASURE_JOURNAL_PATH)'
    task :reapply, [:journal_path] => :environment do |_task, args|
      path = args[:journal_path].presence || Inclamo::Erasure.journal_path
      abort 'No journal: give its path, or set INCLAMO_ERASURE_JOURNAL_PATH.' unless path
      abort "No journal at #{path}." unless File.file?(path)

      started = Inclamo::Erasure::Reapply.new(path).call
      if started.empty?
        puts 'Nothing to erase again.'
        next
      end

      # Chatwoot leaves part of an account's deletion to the background
      # workers: wait for them for a while, then say what is left to them.
      wait = Integer(ENV.fetch('WAIT', '600'), 10, exception: false) || 600
      deadline = Time.current + wait
      stores, shoppers = started.partition { |one| one.line['kind'] == 'store' }
      records = stores.map(&:record)
      sleep 5 until records.all? { |record| record.reload.state == 'erased' } || Time.current > deadline

      stores.each do |one|
        line = one.line
        state = one.record.reload.state == 'erased' ? 'erased again' : 'still being erased by the background workers (the record says erasing)'
        puts "Store #{line['shop_domain']}, account #{line['account_id']} (erased #{line['completed_at']}): #{state}"
      end
      # A shopper's contacts are deleted at once; their conversations go in
      # the background workers' jobs.
      shoppers.each do |one|
        line = one.line
        ticket = one.record ? ', its ticket finished again' : ''
        puts "Shopper of store #{line['shop_domain']}, account #{line['account_id']}, request #{line['request_id']} " \
             "(erased #{line['completed_at']}): #{one.erased} contact(s) erased again#{ticket}"
      end
    end
  end
end
