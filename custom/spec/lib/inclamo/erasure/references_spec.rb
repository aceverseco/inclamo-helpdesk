# frozen_string_literal: true

require 'rails_helper'

# The list of the overlay's columns that name an account, a contact, a
# conversation or a Shopify order: an erasure must reach every row that holds
# one, so a table added without a place on the list fails here.
RSpec.describe Inclamo::Erasure::References do
  let(:connection) { ActiveRecord::Base.connection }

  it 'lists every such column of the overlay, and nothing the database does not have' do
    expect(described_class.unlisted).to eq([])
    expect(described_class.stale).to eq([])
    expect(described_class.found).not_to be_empty
  end

  it 'says of each what the database does to the row' do
    expect(described_class.mismatched).to eq([])
  end

  it 'fails for a table added with such a column and not listed' do
    connection.create_table(:inclamo_spec_erasure_probe) do |t|
      t.bigint :account_id
      t.bigint :conversation_id
      t.string :order_number
      t.string :title
    end

    expect(described_class.unlisted).to contain_exactly(
      %w[inclamo_spec_erasure_probe account_id], %w[inclamo_spec_erasure_probe conversation_id], %w[inclamo_spec_erasure_probe order_number]
    )
  end

  it 'fails for a listed column whose foreign key acts otherwise than the list says' do
    stub_const("#{described_class}::LIST", described_class::LIST.merge('inclamo_shopify_connections' => { 'account_id' => :nullify }))

    expect(described_class.mismatched).to eq([['inclamo_shopify_connections', 'account_id', :nullify, :cascade]])
  end

  it 'names the tables an erasure must empty before it destroys the account' do
    expect(described_class.holding_account).to contain_exactly(
      'inclamo_ai_identity_verifications', 'inclamo_ai_policies', 'inclamo_ai_proposals', 'inclamo_setup_states'
    )
  end
end
