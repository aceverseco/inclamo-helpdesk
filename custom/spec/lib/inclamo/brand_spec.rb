# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Brand do
  let(:name_of) { ->(configs) { configs.find { |config| config['name'] == 'INSTALLATION_NAME' }['value'] } }
  let(:chatwoot_defaults) { YAML.safe_load(Rails.root.join('config/installation_config.yml').read) }

  it 'names a new installation after the product' do
    expect(name_of.call(chatwoot_defaults)).to eq('Chatwoot')
    expect(name_of.call(ConfigLoader.new.general_configs)).to eq('Inclamo')
  end

  it "leaves every other default of Chatwoot's installation config as it is" do
    others = ->(configs) { configs.reject { |config| config['name'] == 'INSTALLATION_NAME' } }

    expect(others.call(ConfigLoader.new.general_configs)).to eq(others.call(chatwoot_defaults))
  end

  # The page itself needs the built interface; the name it is given is read here.
  describe 'the dashboard' do
    def name_shown_when_installation_is(value)
      config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_NAME')
      config.value = value
      config.save!
      GlobalConfig.clear_cache
      controller = DashboardController.new
      controller.send(:set_global_config)
      controller.instance_variable_get(:@global_config)['INSTALLATION_NAME']
    end

    it "shows the product's name while the installation carries Chatwoot's default" do
      expect(name_shown_when_installation_is('Chatwoot')).to eq('Inclamo')
    end

    it 'shows a name the owner chose' do
      expect(name_shown_when_installation_is('Acme Support')).to eq('Acme Support')
    end
  end
end
