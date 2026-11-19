# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')

# Applying the journal again after a restore brings back a shopper whose data
# was deleted (docs/app-store-erasure.md §7): the shopper is found again by
# the journal's digests, deleted with what the overlay keeps about them, and
# the ticket the restore brought back is finished as it was.
RSpec.describe Inclamo::Erasure::Reapply, type: :request do
  include_context 'with app provisioning'
  include ShopperRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:dir) { Dir.mktmpdir('inclamo-erasure-journal') }
  let(:journal) { File.join(dir, 'erasures.jsonl') }
  let(:account) { provisioned.account }
  let(:admin) { store_administrator }
  before { active_store }

  let!(:shopper) { shopper_contact(account) }

  around do |example|
    travel_to(now) do
      with_modified_env(INCLAMO_ERASURE_JOURNAL_PATH: journal) { example.run }
    end
  ensure
    FileUtils.remove_entry(dir)
  end


  it 'writes the line of a completed shopper\'s erasure that it later applies' do
    ask_shopper_erasure(order_ids: ['299938'])
    request = shopper_request
    travel 1.day
    perform_enqueued_jobs { Inclamo::Erasure::ShopperActions.delete!(request, admin) }

    line = JSON.parse(File.read(journal))
    expect(line.keys).to contain_exactly('kind', 'request_id', 'shop_domain', 'account_id', 'email_digest', 'phone_digest', 'order_ids',
                                         'done_by', 'done_by_id', 'received_at', 'completed_at')
    expect(line).to include('kind' => 'shopper', 'request_id' => request.id, 'order_ids' => ['299938'], 'done_by' => 'team',
                            'done_by_id' => admin.id, 'completed_at' => '2026-11-21T10:00:00Z')
  end

  describe 'after a restore' do
    # The database as a backup taken before the deletion holds it: the shopper
    # with two conversations, the erasure's ticket waiting with a colleague's
    # note naming the shopper, and another shopper's ticket held. The journal,
    # outside the database, holds the line the completed deletion wrote.
    let!(:request) do
      ask_shopper_erasure(order_ids: ['299938'])
      shopper_request
    end
    let!(:held) do
      shopper_contact(account, email: 'kim@example.com', phone: '+15550000002')
      ask_shopper_erasure(shopper: { email: 'kim@example.com' })
      shopper_request.tap { |one| Inclamo::Erasure::ShopperActions.hold!(one, admin, 'open payment dispute') }
    end

    before do
      Inclamo::Erasure::Ticket.note!(ticket_of(request), 'Called PAT@example.com', author: admin)
      Inclamo::OrderAction.insert!({ account_id: account.id, conversation_id: nil, user_id: admin.id, action_id: 'listed',
                                     action: 'cancel', order_id: 'gid://shopify/Order/299938' })
      entry = Inclamo::Erasure::Journal.shopper_entry(request)
      Inclamo::Erasure::Journal.append(entry.merge(done_by: 'team', done_by_id: admin.id, completed_at: '2026-11-21T10:00:00Z'))
      travel 3.days
    end

    it 'deletes the shopper again, finishes the restored ticket as it was, and leaves a held ticket held' do
      started = perform_enqueued_jobs { described_class.new(journal).call }

      expect(started.map(&:erased)).to eq([1])
      expect(Contact.exists?(shopper.id)).to be(false)
      expect(Conversation.where(contact_id: shopper.id)).to be_empty
      expect(Inclamo::OrderAction.where(action_id: 'listed')).to be_empty
      expect(request.reload).to have_attributes(state: 'done', done_by: 'team', done_by_id: admin.id, email: nil, phone: nil,
                                                completed_at: Time.utc(2026, 11, 21, 10))
      texts = ticket_texts(request)
      expect(texts.join(' ').downcase).not_to include('pat@example.com')
      expect(texts.last).to eq("Done: #{admin.available_name} deleted the shopper's data on 2026-11-21 10:00 UTC.")
      expect(File.readlines(journal).size).to eq(1)
      expect(held.reload).to have_attributes(state: 'held', email: 'kim@example.com')
      expect(Contact.where(account_id: account.id, email: 'kim@example.com')).to exist
    end

    it 'erases nothing more on a second run' do
      perform_enqueued_jobs { described_class.new(journal).call }

      expect { expect(described_class.new(journal).call).to eq([]) }.not_to change(Contact, :count)
    end

    it 'does not take a contact made after the erasure was completed' do
      Contact.where(id: shopper.id).update_all(created_at: Time.utc(2026, 11, 22)) # rubocop:disable Rails/SkipsModelValidations

      described_class.new(journal).call

      expect(Contact.exists?(shopper.id)).to be(true)
    end

    it 'runs as the task the operator is told to run, and says what it erased' do
      task = Rake::Task['inclamo:erasure:reapply']
      task.reenable

      expect { perform_enqueued_jobs { task.invoke(journal) } }
        .to output(/Shopper of store #{ProvisioningRequests::STORE}, account #{account.id}, request #{request.id} \(erased 2026-11-21T10:00:00Z\): 1 contact\(s\) erased again, its ticket finished again/).to_stdout
      task.reenable
      expect { task.invoke(journal) }.to output("Nothing to erase again.\n").to_stdout
    end
  end
end
