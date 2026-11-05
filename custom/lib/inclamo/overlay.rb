# frozen_string_literal: true

module Inclamo
  # Facts about the overlay itself.
  module Overlay
    ROOT = Rails.root.join('custom')

    def self.version
      @version ||= read_version('INCLAMO_VERSION')
    end

    # The Chatwoot release this overlay was built and tested against.
    def self.chatwoot_version
      @chatwoot_version ||= read_version('CHATWOOT_VERSION')
    end

    def self.read_version(name)
      file = ROOT.join(name)
      file.exist? ? file.read.strip : 'unknown'
    end
    private_class_method :read_version
  end
end
