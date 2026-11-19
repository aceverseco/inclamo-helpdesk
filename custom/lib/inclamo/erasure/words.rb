# frozen_string_literal: true

module Inclamo
  module Erasure
    # The words the helpdesk writes into an account for a request about a
    # shopper: the inbox's and the contact's names, the labels' descriptions
    # and the notes of a ticket (inclamo.erasure in custom/config/locales). They
    # are stored text, so they are written in the account's language when the
    # overlay has it, else in English.
    module Words
      module_function

      def t(account, key, **options)
        I18n.t("inclamo.erasure.#{key}", locale: locale(account), **options)
      end

      def locale(account)
        code = account&.locale.to_s.tr('-', '_')
        [code, code.split('_').first].uniq.each do |one|
          next if one.blank? || I18n.available_locales.exclude?(one.to_sym)
          return one.to_sym if I18n.exists?('inclamo.erasure.inbox_name', one.to_sym)
        end
        :en
      end

      # A moment as the notes write it: the same for every reader, in UTC.
      def time(value)
        value&.utc&.strftime('%Y-%m-%d %H:%M UTC')
      end

      def counts(account, contacts, conversations)
        { contacts: t(account, 'contacts', count: contacts), conversations: t(account, 'conversations', count: conversations) }
      end
    end
  end
end
