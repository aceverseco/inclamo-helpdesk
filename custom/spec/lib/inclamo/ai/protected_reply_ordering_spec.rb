# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

# The protected reply against a take-over on another database connection at
# the same moment (ai-reply-ownership, task 2.5). Another thread sees only
# committed rows, so these examples run without the spec's wrapping
# transaction and remove what they made afterwards.
RSpec.describe Inclamo::Ai::ProtectedReply, 'against a concurrent take-over' do
  include AiServiceStubs

  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let!(:conversation) { create(:conversation, account: account, inbox: website) }

  # Threads an example started; released and joined even when it fails, so no
  # transaction keeps the row locked while purge runs.
  let(:gates) { [] }
  let(:threads) { [] }

  after do
    gates.each { |gate| gate << true }
    threads.each { |thread| thread.join(5) }
    purge
  end

  # Everything of the account, by account_id, with foreign keys off for the
  # session; then the users made for it and every access token they held.
  def purge
    connection = ActiveRecord::Base.connection
    user_ids = AccountUser.where(account_id: account.id).pluck(:user_id)
    bot_ids = AgentBot.where(account_id: account.id).pluck(:id)
    inbox_ids = Inbox.where(account_id: account.id).pluck(:id)
    connection.execute('SET session_replication_role = replica')
    ContactInbox.where(inbox_id: inbox_ids).delete_all
    AccessToken.where(owner_type: 'User', owner_id: user_ids).or(AccessToken.where(owner_type: 'AgentBot', owner_id: bot_ids)).delete_all
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

  def gate
    Queue.new.tap { |queue| gates << queue }
  end

  def protected_reply(content)
    in_thread { described_class.new(conversation: Conversation.find(conversation.id), bot: bot, content: content).perform }
  end

  def waits_for_the_lock(thread)
    sleep 0.3
    thread.alive?
  end

  it 'refuses a reply that arrives while an assignment is not committed yet' do
    taken = Queue.new
    release = gate
    take_over = in_thread do
      Conversation.transaction do
        Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: agent.id).perform
        taken << true
        release.pop
      end
    end
    taken.pop

    replying = protected_reply('Late')
    expect(waits_for_the_lock(replying)).to be(true)
    release << true
    take_over.join

    expect(replying.value).to be_nil
    expect(Message.where(conversation_id: conversation.id, content: 'Late')).to be_empty
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
  end

  it "refuses a reply that arrives while a person's public reply is not committed yet" do
    taken = Queue.new
    release = gate
    take_over = in_thread do
      Conversation.transaction do
        Messages::MessageBuilder.new(agent, Conversation.find(conversation.id), ActionController::Parameters.new(content: 'I am here')).perform
        taken << true
        release.pop
      end
    end
    taken.pop

    replying = protected_reply('Late')
    expect(waits_for_the_lock(replying)).to be(true)
    release << true
    take_over.join

    expect(replying.value).to be_nil
    expect(Message.where(conversation_id: conversation.id).pluck(:content)).to eq(['I am here'])
    expect(conversation.reload.status).to eq('open')
  end

  it "makes a person's reply wait, before it is saved, for a reply that holds the conversation" do
    locked = Queue.new
    release = gate
    allow_any_instance_of(Messages::MessageBuilder).to receive(:perform).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      if original.receiver.instance_variable_get(:@user).is_a?(AgentBot)
        locked << true
        release.pop
      end
      original.call(*args)
    end

    replying = protected_reply('In time')
    locked.pop
    person = in_thread { Messages::MessageBuilder.new(agent, Conversation.find(conversation.id), ActionController::Parameters.new(content: 'I am here')).perform }
    expect(waits_for_the_lock(person)).to be(true)
    # The person's reply is not saved while it waits: it cannot slip in before the agent's.
    expect(Message.where(conversation_id: conversation.id, content: 'I am here')).to be_empty
    release << true
    reply = replying.value
    persons = person.value

    expect(reply).to be_a(Message)
    expect(persons.id).to be > reply.id
    expect(Message.where(conversation_id: conversation.id).reorder(:id).pluck(:content)).to eq(['In time', 'I am here'])
    expect(conversation.reload.status).to eq('open')
  end

  it 'lets a take-over wait for a reply that holds the conversation; the reply comes first' do
    locked = Queue.new
    release = gate
    allow_any_instance_of(Messages::MessageBuilder).to receive(:perform).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      if original.receiver.instance_variable_get(:@user).is_a?(AgentBot)
        locked << true
        release.pop
      end
      original.call(*args)
    end

    replying = protected_reply('In time')
    locked.pop
    take_over = in_thread do
      Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: agent.id).perform
    end
    expect(waits_for_the_lock(take_over)).to be(true)
    release << true
    message = replying.value
    take_over.join

    expect(message).to be_a(Message)
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    expect(conversation.status_changed_at).to be >= message.created_at
  end
end
