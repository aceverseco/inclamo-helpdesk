# frozen_string_literal: true

require 'rails_helper'

# A client pages through its source's events by id (the intake's `sync`
# reads `id > cursor`). Two requests of one source reconcile at once on
# separate database connections; another thread sees only committed rows, so
# these examples run without the spec's wrapping transaction and remove what
# they made afterwards.
RSpec.describe Inclamo::Support::Feed, 'paged by a client while two requests of one source reconcile' do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let!(:key) { OpenSSL::PKey.generate_key('ED25519') }
  let!(:source) do
    Inclamo::Support::Source.create!(reference: SecureRandom.uuid, public_key: key.public_to_pem, base_url: 'https://synthetic.example.test',
                                     fingerprint: Inclamo::Support::Authentication.fingerprint(key.public_to_pem))
  end
  let!(:first) { mapping('First public reply') }
  let!(:second) { mapping('Second public reply') }

  # Threads an example started; released and joined even when it fails, so no
  # transaction keeps a lock while purge runs.
  let(:gates) { [] }
  let(:threads) { [] }

  after do
    gates.each { |gate| gate << true }
    threads.each { |thread| thread.join(5) }
    purge
  end

  def mapping(reply)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: false, content: reply)
    source.requests.create!(reference: SecureRandom.uuid, local_reference: SecureRandom.uuid, account_key: 'account:1', author_key: 'user:1',
                            author: { 'key' => 'user:1', 'name' => 'Synthetic Author' }, conversation: conversation)
  end

  # Everything of the support account and the source, with foreign keys off
  # for the session; then the users made for it and their access tokens.
  def purge
    connection = ActiveRecord::Base.connection
    user_ids = AccountUser.where(account_id: account.id).pluck(:user_id)
    inbox_ids = Inbox.where(account_id: account.id).pluck(:id)
    connection.execute('SET session_replication_role = replica')
    Inclamo::Support::Event.where(source_id: source.id).delete_all
    Inclamo::Support::CentralRequest.where(source_id: source.id).delete_all
    Inclamo::Support::Source.where(id: source.id).delete_all
    ContactInbox.where(inbox_id: inbox_ids).delete_all
    AccessToken.where(owner_type: 'User', owner_id: user_ids).delete_all
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

  def reconcile(mapping)
    in_thread { described_class.reconcile!(Inclamo::Support::CentralRequest.find(mapping.id)) }
  end

  # What the intake's `sync` gives a client after `cursor`: the ids it pages through.
  def page(cursor)
    Inclamo::Support::Event.where(source_id: source.id).where('id > ?', cursor).order(:id).pluck(:id)
  end

  # Holds the first request's reconciliation, inside its transaction, right
  # after it inserted its first event.
  def hold_first_after_its_first_event
    inserted = Queue.new
    release = gate
    held = false
    allow(described_class).to receive(:event!).and_wrap_original do |original, mapping, *rest|
      original.call(mapping, *rest).tap do
        next if held || mapping.id != first.id

        held = true
        inserted << true
        release.pop
      end
    end
    [inserted, release]
  end

  it 'never lets a client page past an event another reconciliation has not committed yet' do
    inserted, release = hold_first_after_its_first_event
    holding = reconcile(first)
    inserted.pop

    other = reconcile(second)
    other.join(0.5)
    seen = page(0)
    release << true
    [holding, other].each { |thread| thread.join(5) }
    seen += page(seen.last || 0)

    expect(seen).to eq(Inclamo::Support::Event.where(source_id: source.id).order(:id).pluck(:id))
    bodies = Inclamo::Support::Event.where(source_id: source.id).pluck(Arel.sql("payload->>'body'"))
    expect(bodies).to include('First public reply', 'Second public reply')
  end

  it 'lets a reconciliation that adds no event finish while another one holds the feed' do
    described_class.reconcile!(Inclamo::Support::CentralRequest.find(second.id))
    recorded = Inclamo::Support::Event.where(central_request_id: second.id).count
    inserted, release = hold_first_after_its_first_event
    holding = reconcile(first)
    inserted.pop

    unchanged = reconcile(second)
    expect(unchanged.join(2)).to be_truthy
    release << true
    holding.join(5)

    expect(Inclamo::Support::Event.where(central_request_id: second.id).count).to eq(recorded)
  end
end
