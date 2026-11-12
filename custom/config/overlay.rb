# frozen_string_literal: true

# Wires custom/ into the application. Loaded once by
# config/initializers/00_inclamo_overlay.rb, before the autoloader is set up.
# The overlay's own constants are autoloaded, not defined here.

overlay_root = Rails.root.join('custom')
loader = Rails.autoloaders.main

# Chatwoot's extension hook (`prepend_mod_with` and friends) walks the
# namespaces `Enterprise` and `Custom` whenever custom/ exists, and raises when
# one of them is not defined at all (v4.19.1: `false&.const_defined?` in
# config/initializers/01_inject_enterprise_edition_module.rb). The Community
# Edition has no `Enterprise`, and `Custom` exists only once we extend a core
# class. Two empty namespaces keep the hook working; they carry no code.
%i[Enterprise Custom].each do |namespace|
  Object.const_set(namespace, Module.new) unless Object.const_defined?(namespace, false)
end

# Code: every directory under custom/app (except views and frontend sources)
# and custom/lib become autoload roots. They are eager loaded in production
# together with the rest of the application.
Dir[overlay_root.join('app/*').to_s].each do |dir|
  next unless File.directory?(dir)
  next if %w[views javascript assets].include?(File.basename(dir))

  loader.push_dir(dir)
end

overlay_lib = overlay_root.join('lib')
if overlay_lib.exist?
  loader.push_dir(overlay_lib.to_s)
  loader.ignore(overlay_lib.join('tasks').to_s)
end

# Middleware lives for the process lifetime, outside the reloadable loader.
body_limit = overlay_lib.join('inclamo_support_body_limit.rb')
loader.ignore(body_limit.to_s)
require body_limit
Rails.application.config.middleware.insert_before(0, InclamoSupportBodyLimit)

# Routes: drawn before Chatwoot's own on every (re)load of the route set.
overlay_routes = overlay_root.join('config/routes.rb')
if overlay_routes.exist?
  Rails.application.routes.prepend do
    instance_eval(File.read(overlay_routes), overlay_routes.to_s)
  end
end

# Store facts are written, and the order a customer names is tied, before
# Chatwoot evaluates the automation rules of a new conversation. The listener
# has no extension hook of its own, so the overlay prepends to it here, again
# after every reload of the code.
Rails.application.config.to_prepare do
  AutomationRuleListener.prepend(Inclamo::StoreFactsBeforeRules)
  Public::Api::V1::Portals::ArticlesController.prepend(Inclamo::ArticlePreview::PublicGuard)
  SuperAdmin::Devise::SessionsController.prepend(Inclamo::Authentication::SuperAdminSession)
  Message.include(Inclamo::Support::NativeEvents)
  Conversation.include(Inclamo::Support::NativeEvents)
end

# Order steps in macros (see Inclamo::Shopify::MacroSteps). Chatwoot's hook
# only includes modules, which cannot replace a method the class defines, so
# these are prepended here, again after every reload.
Rails.application.config.to_prepare do
  Macro.prepend(Inclamo::Shopify::MacroSteps::Validation)
  Macros::ExecutionService.prepend(Inclamo::Shopify::MacroSteps::Execution)
  MacrosExecutionJob.prepend(Inclamo::Shopify::MacroSteps::Job)
  Api::V1::Accounts::MacrosController.prepend(Inclamo::Shopify::MacroSteps::ExecutionGuard)
end

# Credentials of a store connection, the AI agent's connection code and the
# in-product support's signed material never reach the request log.
Rails.application.config.filter_parameters |= [:client_secret, :access_token, :connection_code, :address, :note]
Rails.application.config.filter_parameters |= [:private_key, :signature, :verification_digest, :code, :bytes]

# Deliveries to the AI service are recorded (Inclamo::Ai::DeliveryRecorder).
# Chatwoot's webhook sender has no extension hook, so it is prepended here,
# again after every code reload.
Rails.application.config.to_prepare do
  Webhooks::Trigger.prepend(Inclamo::Ai::DeliveryRecorder) unless Webhooks::Trigger.ancestors.include?(Inclamo::Ai::DeliveryRecorder)
end

# Locales of the overlay's backend messages.
I18n.load_path += Dir[overlay_root.join('config/locales/**/*.yml').to_s]

# The overlay's tables are created by its own migrations (see
# Inclamo::Overlay::Migrations), so they stay out of Chatwoot's schema dump.
ActiveRecord::SchemaDumper.ignore_tables |= [/\Ainclamo_/]

# The periodic check for missed SLA targets (design D4 of sla-timers), next to
# Chatwoot's own schedule. sidekiq-cron looks for due jobs every 30 seconds, so
# a shorter interval (the end-to-end stack uses a few seconds) shortens that too.
if defined?(Sidekiq::Cron::Job)
  Rails.application.reloader.to_prepare do
    next unless Sidekiq.server?

    seconds = Inclamo::Sla.check_seconds
    Sidekiq::Cron.configure do |config|
      config.cron_poll_interval = seconds if seconds < config.cron_poll_interval.to_i
    end
    Sidekiq::Cron::Job.create(name: 'inclamo_sla_check_job', cron: Inclamo::Sla.check_cron(seconds),
                              class: 'Inclamo::SlaCheckJob', queue: 'scheduled_jobs')
    # Accounts that lack a ready team queue or saved reply get them (Inclamo::Presets).
    Sidekiq::Cron::Job.create(name: 'inclamo_presets_repair_job', cron: '*/10 * * * *',
                              class: 'Inclamo::PresetsRepairJob', queue: 'scheduled_jobs')
  end
end

# Factories of the overlay's specs.
if Rails.env.test? && defined?(FactoryBot)
  factories = overlay_root.join('spec/factories')
  FactoryBot.definition_file_paths |= [factories.to_s] if factories.exist?
end
