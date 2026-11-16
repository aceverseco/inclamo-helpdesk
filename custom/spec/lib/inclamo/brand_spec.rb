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

  describe 'the dashboard', type: :request do
    def set_name(value)
      config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_NAME')
      config.value = value
      config.save!
      GlobalConfig.clear_cache
    end

    it "shows the product's name while the installation carries Chatwoot's default" do
      set_name('Chatwoot')

      get '/app/login'

      expect(response.body).to match(%r{<title>\s*Inclamo\s*</title>})
    end

    it 'shows a name the owner chose' do
      set_name('Acme Support')

      get '/app/login'

      expect(response.body).to match(%r{<title>\s*Acme Support\s*</title>})
    end
  end
end
