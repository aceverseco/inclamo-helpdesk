# frozen_string_literal: true

class Inclamo::Support::Installation < ApplicationRecord
  self.table_name = 'inclamo_support_installations'
  # Every production Chatwoot installation already needs secret_key_base. Using
  # a purpose-specific derived key avoids requiring the optional Shopify/AR
  # encryption configuration before an ordinary self-hosted member can get help.
  def private_key
    self.class.encryptor.decrypt_and_verify(self[:private_key], purpose: 'support-installation')
  end

  def private_key=(value)
    self[:private_key] = self.class.encryptor.encrypt_and_sign(value, purpose: 'support-installation')
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key('inclamo-support-installation', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
  end

  def self.identity
    create_or_find_by!(purpose: 'support') do |record|
      key = OpenSSL::PKey.generate_key('ED25519')
      record.private_key = key.private_to_pem
      record.public_key = key.public_to_pem
    end
  end
end
