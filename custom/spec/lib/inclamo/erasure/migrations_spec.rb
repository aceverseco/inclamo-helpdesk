# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/db/migrate/20261120213000_add_erasure_to_inclamo_provisioned_accounts')
require Rails.root.join('custom/db/migrate/20261120213100_create_inclamo_erasure_requests')

# The two migrations of the store's erasure run down and up again, and the
# store's row keeps one store per account throughout.
RSpec.describe 'The erasure migrations' do # rubocop:disable RSpec/DescribeClass
  let(:connection) { ActiveRecord::Base.connection }

  def quietly(&)
    ActiveRecord::Migration.suppress_messages(&)
  end

  # Each statement in a savepoint of its own: a refused one leaves the
  # example's transaction usable.
  def insert_row(domain, account_id, state = 'active')
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL.squish)
        INSERT INTO inclamo_provisioned_accounts (shop_domain, account_id, state, created_at, updated_at)
        VALUES (#{connection.quote(domain)}, #{account_id.nil? ? 'NULL' : Integer(account_id)}, #{connection.quote(state)}, now(), now())
      SQL
    end
  end

  def constraints
    connection.check_constraints(:inclamo_provisioned_accounts).map(&:name)
  end

  after do
    Inclamo::ProvisionedAccount.reset_column_information
    Inclamo::ErasureRequest.reset_column_information
  end

  it 'run down and up again' do
    quietly do
      CreateInclamoErasureRequests.new.migrate(:down)
      AddErasureToInclamoProvisionedAccounts.new.migrate(:down)
    end
    expect(connection.table_exists?(:inclamo_erasure_requests)).to be(false)
    expect(connection.column_exists?(:inclamo_provisioned_accounts, :erase_after)).to be(false)
    expect(constraints).not_to include('inclamo_provisioned_accounts_erased_account')
    expect { insert_row('down.myshopify.com', nil, 'erased') }.to raise_error(ActiveRecord::StatementInvalid, /state/)

    quietly do
      AddErasureToInclamoProvisionedAccounts.new.migrate(:up)
      CreateInclamoErasureRequests.new.migrate(:up)
    end
    expect(connection.table_exists?(:inclamo_erasure_requests)).to be(true)
    expect(connection.column_exists?(:inclamo_provisioned_accounts, :erase_after, :datetime)).to be(true)
    expect(connection.column_exists?(:inclamo_provisioned_accounts, :erased_at, :datetime)).to be(true)
    expect(constraints).to include('inclamo_provisioned_accounts_state', 'inclamo_provisioned_accounts_erased_account')
  end

  it 'keeps refusing two rows for one account, and lets erased stores keep no account' do
    account = create(:account)
    insert_row('first.myshopify.com', account.id)

    expect { insert_row('second.myshopify.com', account.id) }.to raise_error(ActiveRecord::RecordNotUnique)
    insert_row('erased-1.myshopify.com', nil, 'erased')
    insert_row('erased-2.myshopify.com', nil, 'erasing')
    expect(connection.select_value("SELECT count(*) FROM inclamo_provisioned_accounts WHERE account_id IS NULL")).to eq(2)
  end

  it 'refuses an erased store that still names an account, and an unknown state' do
    account = create(:account)

    expect { insert_row('erased.myshopify.com', account.id, 'erased') }.to raise_error(ActiveRecord::StatementInvalid, /erased_account/)
    expect { insert_row('gone.myshopify.com', nil, 'gone') }.to raise_error(ActiveRecord::StatementInvalid, /state/)
  end

  it 'refuses a request of an unknown kind, or in a state of another kind' do
    insert = lambda do |kind, state|
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL.squish)
          INSERT INTO inclamo_erasure_requests (kind, shop_domain, state, received_at, created_at, updated_at)
          VALUES (#{connection.quote(kind)}, 'a.myshopify.com', #{connection.quote(state)}, now(), now(), now())
        SQL
      end
    end

    expect { insert.call('store', 'scheduled') }.not_to raise_error
    expect { insert.call('shopper_erasure', 'scheduled') }.to raise_error(ActiveRecord::StatementInvalid, /state/)
    expect { insert.call('store', 'waiting') }.to raise_error(ActiveRecord::StatementInvalid, /state/)
    expect { insert.call('anything', 'done') }.to raise_error(ActiveRecord::StatementInvalid, /kind/)
  end
end
