# frozen_string_literal: true

namespace :inclamo do
  namespace :provisioning do
    desc 'Tie an account made by hand to its Shopify store: inclamo:provisioning:link[shop_domain,account_id]'
    task :link, [:shop_domain, :account_id] => :environment do |_task, args|
      row = Inclamo::Provisioning.link!(args[:shop_domain], args[:account_id])
      puts "#{row.shop_domain} is linked to account #{row.account_id} (#{row.state})"
    rescue Inclamo::Provisioning::LinkRefused => e
      abort "Not linked: #{e.message}"
    end
  end
end
