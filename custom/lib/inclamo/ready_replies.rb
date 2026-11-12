# frozen_string_literal: true

module Inclamo
  # The saved replies every account starts with, one per support category
  # (capability ready-replies). They are ordinary Chatwoot saved replies. What
  # was offered is recorded per account, so a reply the store edited is never
  # rewritten and one it deleted never comes back; where the store already has
  # a reply under the short code, the ready one is not created.
  module ReadyReplies
    KIND = 'ready_reply'
    # category => short code
    READY = {
      'delivery' => 'delivery-status',
      'cancellation' => 'cancel-confirm',
      'damage' => 'damage-photos',
      'missing_parts' => 'missing-part',
      'return' => 'return-start'
    }.freeze

    module_function

    def call(account)
      READY.each { |key, short_code| install(account, key, short_code) }
    end

    def content(key)
      I18n.t("inclamo.ready_replies.#{key}")
    end

    # The record of the offer and the reply are made together, so a failure
    # leaves neither and the next run tries again.
    def install(account, key, short_code)
      return if Inclamo::PresetInstall.exists?(account_id: account.id, kind: KIND, key: key)

      Inclamo::PresetInstall.transaction(requires_new: true) do
        taken = account.canned_responses.exists?(short_code: short_code)
        Inclamo::PresetInstall.create!(account: account, kind: KIND, key: key, created: !taken, installed_at: Time.current)
        account.canned_responses.create!(short_code: short_code, content: content(key)) unless taken
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
