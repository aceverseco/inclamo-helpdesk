# frozen_string_literal: true

module Inclamo
  module TeamQueues
    # Gives an account the ready queues it does not have yet, and the labels
    # they list by (design D6). A queue is found by its key and never deleted,
    # so running this again creates nothing and leaves the name, the order and
    # the hidden state an administrator set as they are. A queue created later
    # than the others takes its shipped place among them (TeamQueues.place!).
    module Installer
      module_function

      def call(account)
        TeamQueues.labels.each { |title| label!(account, title) }
        READY.each_key { |key| queue!(account, key) }
      end

      def queue!(account, key)
        return if Inclamo::TeamQueue.exists?(account_id: account.id, key: key)

        Inclamo::TeamQueue.transaction(requires_new: true) do
          last = Inclamo::TeamQueue.where(account_id: account.id).maximum(:position) || 0
          queue = Inclamo::TeamQueue.create!(account: account, key: key, name: TeamQueues.shipped_name(key), position: last + 1,
                                             query: TeamQueues.shipped_query(key))
          TeamQueues.place!(queue)
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        raise unless Inclamo::TeamQueue.exists?(account_id: account.id, key: key)
      end

      # The account's label, created when missing. A store's own label of the
      # same title is used as it is.
      def label!(account, title)
        account.labels.find_by(title: title) || Label.transaction(requires_new: true) do
          account.labels.create!(
            title: title, color: LABEL_COLORS.fetch(title, DEFAULT_LABEL_COLOR),
            description: I18n.t("inclamo.team_queues.labels.#{title.tr('-', '_')}"), show_on_sidebar: false
          )
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        account.labels.find_by(title: title) || raise
      end
    end
  end
end
