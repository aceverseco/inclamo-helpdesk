# frozen_string_literal: true

module Inclamo
  # The product's name where Chatwoot would show its own. Both modules are
  # prepended in custom/config/overlay.rb; no file of Chatwoot is changed.
  module Brand
    NAME = 'Inclamo'
    CHATWOOT_NAME = 'Chatwoot'

    # ConfigLoader: a new installation is named after the product. The rest of
    # config/installation_config.yml is read as Chatwoot wrote it.
    module InstallationDefaults
      def general_configs
        @inclamo_general_configs ||= super.map do |config|
          config['name'] == 'INSTALLATION_NAME' ? config.merge('value' => NAME) : config
        end.freeze
      end
    end

    # DashboardController: an installation that still carries Chatwoot's
    # default name (set up before the overlay) shows the product's.
    module DashboardName
      private

      def set_global_config
        super
        @global_config['INSTALLATION_NAME'] = NAME if @global_config['INSTALLATION_NAME'] == CHATWOOT_NAME
      end
    end
  end
end
