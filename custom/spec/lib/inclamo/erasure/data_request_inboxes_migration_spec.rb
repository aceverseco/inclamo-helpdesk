# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/db/migrate/20261121210500_create_inclamo_data_request_inboxes')

# The table that says which inbox of an account holds the tickets about
# shoppers, and their contact: one per account, gone with the account or the
# inbox, and emptied when the contact is deleted.
RSpec.describe 'The data requests inbox migration' do # rubocop:disable RSpec/DescribeClass
  let(:connection) { ActiveRecord::Base.connection }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }

  after { Inclamo::DataRequestInbox.reset_column_information }

  it 'runs down and up again' do
    ActiveRecord::Migration.suppress_messages { CreateInclamoDataRequestInboxes.new.migrate(:down) }
    expect(connection.table_exists?(:inclamo_data_request_inboxes)).to be(false)

    ActiveRecord::Migration.suppress_messages { CreateInclamoDataRequestInboxes.new.migrate(:up) }
    expect(connection.table_exists?(:inclamo_data_request_inboxes)).to be(true)
    expect(connection.index_exists?(:inclamo_data_request_inboxes, :account_id, unique: true)).to be(true)
  end

  it 'keeps one per account, goes with its inbox, and forgets a deleted contact' do
    place = Inclamo::DataRequestInbox.create!(account: account, inbox: inbox, contact: contact)

    second = create(:inbox, account: account)
    expect { connection.transaction(requires_new: true) { Inclamo::DataRequestInbox.create!(account: account, inbox: second) } }
      .to raise_error(ActiveRecord::RecordNotUnique)
    connection.execute("DELETE FROM contacts WHERE id = #{contact.id}")
    expect(place.reload.contact_id).to be_nil
    connection.execute("DELETE FROM inboxes WHERE id = #{inbox.id}")
    expect(Inclamo::DataRequestInbox.exists?(place.id)).to be(false)
  end
end
