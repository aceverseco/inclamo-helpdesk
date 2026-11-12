# frozen_string_literal: true

namespace :inclamo do
  namespace :support do
    desc 'Print the public source identity; never prints the private signing key'
    task identity: :environment do
      identity = Inclamo::Support::Installation.identity
      puts JSON.generate(source_id: identity.source_id, fingerprint: Inclamo::Support::Authentication.fingerprint(identity.public_key))
    end

    desc 'Central operations only: trust a source as hosted after checking its fingerprint'
    task :trust_hosted, [:source_id, :fingerprint] => :environment do |_task, args|
      abort 'Enable central intake on the support installation first' unless Inclamo::Support.central?
      source = Inclamo::Support::Source.find_by!(reference: args.fetch(:source_id), revoked_at: nil)
      abort 'Fingerprint does not match; no change made' unless source.fingerprint == args.fetch(:fingerprint)
      source.update!(hosted: true)
      puts "Hosted source registered: #{source.reference}"
    end

    desc 'Central operations only: revoke a source credential without deleting conversations'
    task :revoke_source, [:source_id, :fingerprint] => :environment do |_task, args|
      abort 'This task runs only on central intake' unless Inclamo::Support.central?
      source = Inclamo::Support::Source.find_by!(reference: args.fetch(:source_id))
      abort 'Fingerprint does not match; no change made' unless source.fingerprint == args.fetch(:fingerprint)
      source.update!(revoked_at: Time.current)
      Inclamo::Support::Recipient.where(source_id: source.id).update_all(active: false, verified_at: nil)
      puts "Source revoked: #{source.reference}"
    end

    desc 'Create a distinct identity on an unused clone; refuses to orphan existing support history'
    task new_clone_identity: :environment do
      abort 'This installation contains support history; restore a clone without support tables before enrollment' if Inclamo::Support::Request.exists?
      Inclamo::Support::Installation.transaction do
        Inclamo::Support::Installation.where(purpose: 'support').destroy_all
        Inclamo::Support::Installation.identity
      end
      puts 'New local support identity created. Enrollment occurs on first submission.'
    end
  end
end
