# frozen_string_literal: true

module Inclamo
  module Ai
    # The agent's labels in an account and on a conversation (design D6, D7).
    # Chatwoot's own label call replaces every label of a conversation; this
    # adds, under a lock, and keeps the team's.
    module Labels
      module_function

      # The fixed labels of the AI service, with their meanings. A label the
      # account already has under the same title is left as it is.
      def ensure_fixed!(account)
        LABELS.each { |title, description| ensure_label!(account, title, description) }
      end

      def valid_name?(name)
        name.is_a?(String) && name.length <= LABEL_MAX_LENGTH && LABEL_FORMAT.match?(name)
      end

      # Adds `names` to the conversation and answers its full list. A name the
      # account lacks becomes an account label, so the dashboard shows it.
      def add(conversation, names)
        names.each { |name| ensure_label!(conversation.account, name, ADDED_LABEL_DESCRIPTION) }
        conversation.with_lock do
          current = conversation.label_list.to_a
          missing = names - current
          conversation.update!(label_list: current + missing) if missing.any?
        end
        conversation.label_list.to_a
      end

      def ensure_label!(account, title, description)
        account.labels.find_by(title: title) ||
          account.labels.create!(title: title, description: description, color: LABEL_COLOR, show_on_sidebar: false)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Made at the same moment by another request.
        account.labels.find_by!(title: title)
      end
    end
  end
end
