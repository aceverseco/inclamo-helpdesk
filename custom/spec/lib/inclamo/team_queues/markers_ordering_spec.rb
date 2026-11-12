# frozen_string_literal: true

require 'rails_helper'

# `sla-overdue` against a label added on another database connection at the
# same moment. Another thread sees only committed rows, so these examples run
# without the spec's wrapping transaction and remove what they made afterwards
# (the pattern of protected_reply_ordering_spec.rb).
RSpec.describe Inclamo::TeamQueues::Markers, 'against a label added at the same moment' do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:policy) { Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 7_200) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:gates) { [] }
  let(:threads) { [] }

  before do
    Inclamo::Sla::Timers.apply!(conversation)
    Inclamo::Ai::Labels.ensure_fixed!(account)
  end

  after do
    gates.each { |gate| gate << true }
    threads.each { |thread| thread.join(5) }
    purge
  end

  def purge
    connection = ActiveRecord::Base.connection
    user_ids = AccountUser.where(account_id: account.id).pluck(:user_id)
    inbox_ids = Inbox.where(account_id: account.id).pluck(:id)
    conversation_ids = Conversation.where(account_id: account.id).pluck(:id)
    connection.execute('SET session_replication_role = replica')
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: conversation_ids).delete_all
    Inclamo::SlaTimer.where(conversation_id: conversation_ids).delete_all
    ContactInbox.where(inbox_id: inbox_ids).delete_all
    connection.tables.each do |table|
      next unless connection.column_exists?(table, :account_id)

      connection.execute("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
    end
    User.where(id: user_ids).delete_all
    Account.where(id: account.id).delete_all
  ensure
    connection.execute('SET session_replication_role = origin')
  end

  def in_thread(&block)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }.tap do |thread|
      thread.report_on_exception = false
      threads << thread
    end
  end

  # The AI agent's hand-over label, added and held uncommitted until released.
  def hand_over_label_held
    added = Queue.new
    release = Queue.new.tap { |queue| gates << queue }
    thread = in_thread do
      Conversation.transaction do
        Inclamo::Ai::Labels.add(Conversation.find(conversation.id), ['inclamo_handover'])
        added << true
        release.pop
      end
    end
    added.pop
    [thread, release]
  end

  def stored
    fresh = Conversation.find(conversation.id)
    [fresh.label_list.sort, fresh.cached_label_list_array.sort]
  end

  it 'the mark of a missed target waits for the other label and keeps it' do
    holder, release = hand_over_label_held

    marking = in_thread { Inclamo::Sla::Timers.check_due!(conversation.created_at + 3.hours) }
    sleep 0.3
    expect(marking).to be_alive
    release << true
    [holder, marking].each { |thread| thread.join(10) }

    expect(stored).to eq([%w[inclamo_handover sla-missed sla-overdue]] * 2)
  end

  it 'taking the label off waits for the other label and keeps it' do
    Inclamo::Sla::Timers.check_due!(conversation.created_at + 3.hours)
    Inclamo::SlaTimer.where(conversation_id: conversation.id).update_all(first_response_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    holder, release = hand_over_label_held

    removing = in_thread { described_class.sync_overdue(conversation.id) }
    sleep 0.3
    expect(removing).to be_alive
    release << true
    [holder, removing].each { |thread| thread.join(10) }

    expect(stored).to eq([%w[inclamo_handover sla-missed]] * 2)
  end
end
