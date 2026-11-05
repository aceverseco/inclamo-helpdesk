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

# Routes: drawn before Chatwoot's own on every (re)load of the route set.
overlay_routes = overlay_root.join('config/routes.rb')
if overlay_routes.exist?
  Rails.application.routes.prepend do
    instance_eval(File.read(overlay_routes), overlay_routes.to_s)
  end
end

# Locales of the overlay's backend messages.
I18n.load_path += Dir[overlay_root.join('config/locales/**/*.yml').to_s]

# The overlay's tables are created by its own migrations (see
# Inclamo::Overlay::Migrations), so they stay out of Chatwoot's schema dump.
ActiveRecord::SchemaDumper.ignore_tables |= [/\Ainclamo_/]

# Factories of the overlay's specs.
if Rails.env.test? && defined?(FactoryBot)
  factories = overlay_root.join('spec/factories')
  FactoryBot.definition_file_paths |= [factories.to_s] if factories.exist?
end
