# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')

# The daily erasure run and the tickets about one shopper
# (docs/app-store-erasure.md §4.2, §5, §7): the automatic deletion when nobody
# deleted or held, holds and their lifting, finishing and cleaning a ticket,
# reminders, and what the record keeps.
RSpec.describe Inclamo::ErasureCheckJob, type: :request do
  include_context 'with app provisioning'
  include ShopperRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }
  let(:admin) { store_administrator }
  before { active_store }

  let!(:shopper) { shopper_contact(account) }
  let(:dir) { Dir.mktmpdir('inclamo-erasure-journal') }
  let(:journal) { File.join(dir, 'erasures.jsonl') }

  around do |example|
    travel_to(now) do
      with_modified_env(INCLAMO_ERASURE_JOURNAL_PATH: journal) { example.run }
    end
  ensure
    FileUtils.remove_entry(dir)
  end


  def erasure(**)
    ask_shopper_erasure(**)
    shopper_request
  end

  def notes(request)
    Message.where(conversation_id: request.reload.conversation_id).reorder(:id).to_a
  end

  describe 'the automatic deletion' do
    it 'deletes a waiting erasure whose date has passed, and the ticket says it was done automatically' do
      request = erasure
      travel 14.days + 1.minute

      run_erasures

      expect(Contact.exists?(shopper.id)).to be(false)
      expect(Conversation.where(contact_id: shopper.id)).to be_empty
      expect(request.reload).to have_attributes(state: 'done', done_by: 'automatic', done_by_id: nil, completed_at: now + 14.days + 1.minute)
      expect(notes(request).last.content).to eq("Done: nobody deleted or held, so the helpdesk deleted the shopper's data on 2026-12-04 10:01 UTC.")
      expect(notes(request).last.sender).to be_nil
      expect(notes(request).map(&:content).grep(/inactivity/)).to eq([])
      expect(ticket_of(request).status).to eq('resolved')
      expect(events_of.last).to eq('shopper_deleted')
    end

    it 'leaves a request that is not yet due' do
      request = erasure
      travel 14.days - 1.minute

      run_erasures

      expect(Contact.exists?(shopper.id)).to be(true)
      expect(request.reload.state).to eq('waiting')
    end

    it 'leaves a held request, whose data survives its date' do
      request = erasure
      Inclamo::Erasure::ShopperActions.hold!(request, admin, 'open payment dispute')
      travel 40.days

      run_erasures

      expect(Contact.exists?(shopper.id)).to be(true)
      expect(shopper.conversations.count).to eq(2)
      expect(request.reload).to have_attributes(state: 'held', hold_reason: 'open payment dispute', held_by_id: admin.id, held_at: now)
    end

    it 'does not do twice a request done between its choice and its lock' do
      request = erasure
      travel 15.days
      chosen = Inclamo::ErasureRequest.find(request.id)
      perform_enqueued_jobs { Inclamo::Erasure::ShopperActions.delete!(request, admin) }

      expect(Inclamo::Erasure::ShopperActions.delete_automatically!(chosen)).to be(false)

      expect(chosen.reload).to have_attributes(done_by: 'team', done_by_id: admin.id)
      expect(notes(request).count { |note| note.content.start_with?('Done:') }).to eq(1)
      expect(events_of.count('shopper_deleted')).to eq(1)
    end

    it 'deletes in a suspended account all the same' do
      request = erasure
      remove_app
      travel 15.days

      run_erasures

      expect(Contact.exists?(shopper.id)).to be(false)
      expect(request.reload.done_by).to eq('automatic')
    end

    it 'leaves a data request alone, whatever its age' do
      ask_data_request
      travel 60.days

      run_erasures

      expect(Contact.exists?(shopper.id)).to be(true)
      expect(shopper_request('shopper_data_request').state).to eq('waiting')
    end

    it 'goes on with the other requests when one fails, and tries it again at the next run' do
      failing = erasure
      shopper_contact(account, email: 'kim@example.com', phone: '+15550000002')
      other = erasure(shopper: { email: 'kim@example.com' })
      travel 15.days
      allow(Rails.logger).to receive(:error)
      allow(Inclamo::Erasure::ShopperDeletion).to receive(:call).and_call_original
      allow(Inclamo::Erasure::ShopperDeletion).to receive(:call).with(having_attributes(id: failing.id)).and_raise('store down')

      run_erasures

      expect(failing.reload.state).to eq('waiting')
      expect(other.reload.state).to eq('done')
      expect(Rails.logger).to have_received(:error).with(/ALERT the automatic deletion of request #{failing.id}/)
    end
  end

  describe 'a hold lifted' do
    it 'before the date keeps the date' do
      request = erasure
      Inclamo::Erasure::ShopperActions.hold!(request, admin, 'open payment dispute')
      travel 3.days
      Inclamo::Erasure::ShopperActions.lift!(request, admin)

      travel_to(now + 14.days - 1.minute)
      run_erasures
      expect(request.reload.state).to eq('waiting')

      travel_to(now + 14.days + 1.minute)
      run_erasures
      expect(request.reload).to have_attributes(state: 'done', done_by: 'automatic')
      expect(Contact.exists?(shopper.id)).to be(false)
    end

    it 'after the date is carried out by the next run' do
      request = erasure
      Inclamo::Erasure::ShopperActions.hold!(request, admin, 'open payment dispute')
      travel 20.days
      run_erasures
      expect(request.reload.state).to eq('held')

      Inclamo::Erasure::ShopperActions.lift!(request, admin)
      run_erasures

      expect(request.reload).to have_attributes(state: 'done', done_by: 'automatic', hold_reason: nil)
      expect(Contact.exists?(shopper.id)).to be(false)
    end
  end

  describe 'a finished ticket' do
    # A colleague wrote the shopper's email, in another letter case, and the
    # phone with spaces into notes of the ticket.
    def team_notes(request)
      ticket = ticket_of(request)
      Inclamo::Erasure::Ticket.note!(ticket, 'Asked PAT@Example.COM about it; also +1 555 625 1199.', author: admin)
      Inclamo::Erasure::Ticket.note!(ticket, 'Another note: 1-555-625-1199 / pat@example.com.', author: admin)
    end

    it 'holds no readable email, phone or reason, names the administrator, and is resolved' do
      request = erasure
      team_notes(request)
      Inclamo::Erasure::ShopperActions.hold!(request, admin, 'call pat@example.com back first')
      travel 1.day

      perform_enqueued_jobs { Inclamo::Erasure::ShopperActions.delete!(request, admin) }

      expect(request.reload).to have_attributes(state: 'done', email: nil, phone: nil, hold_reason: nil, done_by: 'team', done_by_id: admin.id)
      texts = notes(request).map(&:content)
      expect(texts[1]).to eq('Asked [removed] about it; also [removed].')
      expect(texts[2]).to eq('Another note: [removed] / [removed].')
      joined = texts.join(' ').downcase
      expect(joined).not_to include('pat@example.com')
      expect(joined.gsub(/\D/, '')).not_to include('15556251199')
      expect(texts.last).to eq("Done: #{admin.available_name} deleted the shopper's data on 2026-11-21 10:00 UTC.")
      expect(ticket_of(request).status).to eq('resolved')
    end

    it 'does the same for a data request marked answered' do
      ask_data_request
      request = shopper_request('shopper_data_request')
      team_notes(request)

      Inclamo::Erasure::ShopperActions.answered!(request, admin)

      expect(request.reload).to have_attributes(state: 'done', email: nil, phone: nil, done_by: 'team', done_by_id: admin.id)
      joined = notes(request).map(&:content).join(' ').downcase
      expect(joined).not_to include('pat@example.com')
      expect(notes(request).last.content).to include(admin.available_name, 'marked the request answered')
      expect(ticket_of(request).status).to eq('resolved')
      expect(Contact.exists?(shopper.id)).to be(true)
    end
  end

  describe 'reminders' do
    # The reminders' text, after the line that mentions the administrators.
    def reminders(request)
      notes(request).map(&:content).filter_map { |text| text.split("\n\n", 2).last if text.match?(/^Reminder/) }
    end

    it 'reminds a waiting erasure 7 days and 1 day before its date, each once' do
      request = erasure

      [6, 7, 7.5, 12, 13, 13.5].each do |day|
        travel_to(now + day.days)
        run_erasures
      end

      expect(reminders(request)).to eq(['Reminder: if nobody deletes or holds, the helpdesk deletes this shopper\'s data on 2026-12-04 10:00 UTC.'] * 2)
    end

    it 'writes one reminder, not two, after missed days' do
      request = erasure

      travel_to(now + 13.days + 2.hours)
      run_erasures
      travel_to(now + 13.days + 3.hours)
      run_erasures

      expect(reminders(request).size).to eq(1)
    end

    it 'reminds a held erasure every 30 days, and opens its resolved ticket again' do
      request = erasure
      Inclamo::Erasure::ShopperActions.hold!(request, admin, 'open payment dispute')
      expect(ticket_of(request).status).to eq('resolved')

      travel_to(now + 29.days)
      run_erasures
      expect(reminders(request)).to be_empty
      travel_to(now + 30.days + 1.hour)
      run_erasures
      travel_to(now + 31.days)
      run_erasures

      expect(reminders(request)).to eq(['Reminder: the deletion of this shopper\'s data has been held since 2026-11-20 10:00 UTC. ' \
                                        'The request is not met; an administrator can delete the data or lift the hold.'])
      expect(ticket_of(request).status).to eq('open')
      travel_to(now + 61.days)
      run_erasures
      expect(reminders(request).size).to eq(2)
    end

    it 'reminds a waiting data request on days 7, 14, 21 and 27' do
      ask_data_request
      request = shopper_request('shopper_data_request')

      (1..40).each do |day|
        travel_to(now + day.days + 1.minute)
        run_erasures
      end

      expect(reminders(request).size).to eq(4)
      expect(reminders(request).uniq).to eq(['Reminder: a shopper asked for a copy of their data on 2026-11-20 10:00 UTC. ' \
                                             'Answer the shopper and mark the request answered.'])
      expect(request.reload.state).to eq('waiting')
    end

  end

  # A private note of Chatwoot notifies only the people it mentions, and the
  # tickets' inbox has no members: the first note and every reminder mention
  # the account's administrators, so each is notified.
  describe 'who is told' do
    let!(:other_admin) do
      create(:user, account: account, role: :administrator, name: 'Kim (Support) [EU]', display_name: 'Kim (Support) [EU]',
                    email: 'kim.support@example.test')
    end
    let!(:agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, user: agent, inbox: shopper.conversations.first.inbox)
      # A new contact's avatar is looked for at Gravatar by a background job.
      stub_request(:get, /gravatar\.com/).to_return(status: 404)
    end

    # Who Chatwoot told of the note. It keeps one notification for a person
    # and a conversation, the latest (Notification::RemoveDuplicateNotificationJob):
    # a person told of a reminder has the reminder as their notification's message.
    def told_of(note)
      Notification.where(notification_type: 'conversation_mention', primary_actor: note.conversation, secondary_actor: note).pluck(:user_id)
    end

    def mentioned_ids(text)
      text.scan(%r{\(mention://user/(\d+)/[^)]+\)}).flatten.map(&:to_i)
    end

    def data_request_ticket
      ticket_of(perform_enqueued_jobs do
        ask_data_request
        shopper_request('shopper_data_request')
      end)
    end

    it 'the first note of an erasure ticket and of a data-request ticket tells every administrator and no agent' do
      erasure_ticket = ticket_of(perform_enqueued_jobs { erasure })
      asked_ticket = data_request_ticket

      [erasure_ticket, asked_ticket].each do |ticket|
        first = ticket.messages.reorder(:id).first
        expect(mentioned_ids(first.content)).to contain_exactly(admin.id, other_admin.id)
        expect(first.content).to include("[@#{admin.available_name}](mention://user/#{admin.id}/#{ERB::Util.url_encode(admin.available_name)})")
        expect(first.content).to include("[@Kim Support EU](mention://user/#{other_admin.id}/Kim%20Support%20EU)")
        expect(first.content).not_to include('pat@example.com')
        expect(first.content).not_to include('5556251199')
        expect(told_of(first)).to contain_exactly(admin.id, other_admin.id)
      end
      expect(Notification.where(user: agent)).to be_empty
      expect(Mention.where(conversation: erasure_ticket).pluck(:user_id)).to contain_exactly(admin.id, other_admin.id)
    end

    it 'every reminder tells the administrators the account has at that moment, and no agent' do
      erasure_ticket = ticket_of(perform_enqueued_jobs { erasure })
      held = perform_enqueued_jobs do
        shopper_contact(account, email: 'kim@example.com', phone: '+15550000002')
        erasure(shopper: { email: 'kim@example.com' }).tap { |one| Inclamo::Erasure::ShopperActions.hold!(one, admin, 'open payment dispute') }
      end
      asked_ticket = data_request_ticket

      travel_to(now + 7.days + 1.minute)
      perform_enqueued_jobs { run_erasures }

      [erasure_ticket, asked_ticket].each do |ticket|
        reminder = ticket.messages.reorder(:id).last
        expect(reminder.content).to include("\n\nReminder:")
        expect(mentioned_ids(reminder.content)).to contain_exactly(admin.id, other_admin.id)
        expect(told_of(reminder)).to contain_exactly(admin.id, other_admin.id)
      end

      # The administrators change before the held ticket's reminder.
      AccountUser.find_by(account: account, user: other_admin).update!(role: :agent)
      newcomer = create(:user, account: account, role: :administrator)
      travel_to(now + 30.days + 1.hour)
      perform_enqueued_jobs { run_erasures }

      held_ticket = ticket_of(held)
      reminder = held_ticket.messages.reorder(:id).last
      expect(reminder.content).to include("\n\nReminder: the deletion of this shopper")
      expect(mentioned_ids(reminder.content)).to contain_exactly(admin.id, newcomer.id)
      expect(told_of(reminder)).to contain_exactly(admin.id, newcomer.id)
      expect(reminder.content).not_to include('kim@example.com')
      expect(Notification.where(user: agent)).to be_empty
    end

    it 'tells nobody with the notes of the actions: a hold, its lifting, a deletion' do
      request = perform_enqueued_jobs { erasure }
      ticket = ticket_of(request)
      before = Notification.count

      perform_enqueued_jobs do
        Inclamo::Erasure::ShopperActions.hold!(request, admin, 'open payment dispute')
        Inclamo::Erasure::ShopperActions.lift!(request, admin)
        Inclamo::Erasure::ShopperActions.delete!(request, admin)
      end

      expect(Notification.count).to eq(before)
      expect(told_of(ticket.messages.reorder(:id).first)).to contain_exactly(admin.id, other_admin.id)
      expect(ticket.messages.reorder(:id).drop(1).map(&:content).join).not_to include('mention://')
    end
  end

  describe 'the record' do
    it 'keeps the email and phone encrypted while the ticket is open, and only keyed digests afterwards, in the record and the journal' do
      request = erasure
      raw = ActiveRecord::Base.connection.select_one("SELECT email, phone, email_digest, phone_digest FROM inclamo_erasure_requests WHERE id = #{request.id}")
      expect(raw['email']).not_to include('pat@example.com')
      expect(raw['phone']).not_to include('5556251199')
      expect(raw['email_digest']).to eq(OpenSSL::HMAC.hexdigest('SHA256', Inclamo::Erasure::Shoppers.key, 'pat@example.com'))
      expect(raw['phone_digest']).to eq(OpenSSL::HMAC.hexdigest('SHA256', Inclamo::Erasure::Shoppers.key, '15556251199'))
      expect(request.email).to eq('pat@example.com')

      travel 15.days
      run_erasures

      done = ActiveRecord::Base.connection.select_one("SELECT * FROM inclamo_erasure_requests WHERE id = #{request.id}")
      expect(done.values_at('email', 'phone', 'hold_reason')).to eq([nil, nil, nil])
      expect(done.values.join(' ')).not_to include('pat@example.com')
      line = JSON.parse(File.read(journal).lines.last)
      expect(line).to include('kind' => 'shopper', 'request_id' => request.id, 'shop_domain' => ProvisioningRequests::STORE,
                              'account_id' => account.id, 'email_digest' => raw['email_digest'], 'phone_digest' => raw['phone_digest'],
                              'done_by' => 'automatic', 'completed_at' => '2026-12-05T10:00:00Z')
      expect(File.read(journal)).not_to include('pat@example.com')
      expect(File.read(journal)).not_to include('5556251199')
    end

    it 'journals no data request, which deletes nothing' do
      ask_data_request
      Inclamo::Erasure::ShopperActions.answered!(shopper_request('shopper_data_request'), admin)

      expect(File.exist?(journal)).to be(false)
    end

    it 'removes done requests 90 days after they were done, and keeps a held one of any age' do
      done = erasure
      shopper_contact(account, email: 'kim@example.com', phone: '+15550000002')
      held = erasure(shopper: { email: 'kim@example.com' })
      Inclamo::Erasure::ShopperActions.hold!(held, admin, 'open payment dispute')
      perform_enqueued_jobs { Inclamo::Erasure::ShopperActions.delete!(done, admin) }

      travel_to(now + 90.days - 1.minute)
      run_erasures
      expect(Inclamo::ErasureRequest.where(id: done.id)).to exist

      travel_to(now + 90.days + 1.minute)
      run_erasures
      travel_to(now + 400.days)
      run_erasures

      expect(Inclamo::ErasureRequest.where(id: done.id)).not_to exist
      expect(held.reload.state).to eq('held')
    end
  end

  describe 'a ticket and the team\'s queues and SLA timers' do
    it 'starts no SLA timer, even under a policy for every inbox, and enters no team queue' do
      Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 60, all_inboxes: true, business_hours_only: false,
                                 created_at: 1.day.ago)
      Inclamo::TeamQueues::Installer.call(account) if Inclamo::TeamQueue.where(account_id: account.id).none?
      request = erasure
      ticket = ticket_of(request)

      perform_enqueued_jobs { Inclamo::Sla::Timers.apply!(ticket) }
      travel 1.hour
      Inclamo::Sla::Timers.check_due!

      expect(Inclamo::SlaTimer.where(conversation_id: ticket.id)).to be_empty
      expect(ticket.reload.label_list).to eq(['inclamo_erasure_request'])
      queues = Inclamo::TeamQueue.where(account_id: account.id).to_a
      expect(queues.map(&:key)).to include('urgent', 'overdue')
      queues.each do |queue|
        payload = queue.query['payload']
        listed = Conversations::FilterService.new({ payload: payload, page: 1 }.with_indifferent_access, admin, account).perform[:conversations]
        expect(listed.map(&:id)).not_to include(ticket.id), "the queue #{queue.key} lists the ticket"
      end
    end
  end
end
