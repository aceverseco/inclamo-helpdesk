# frozen_string_literal: true

require 'rails_helper'

# The shipped queues against Chatwoot's own conversation filter (design D7):
# a filter key or an operator renamed upstream fails here, on the upgrade branch.
RSpec.describe Inclamo::TeamQueues do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:queues) { Inclamo::TeamQueue.where(account_id: account.id).index_by(&:key) }

  def filter(payload)
    Conversations::FilterService.new({ payload: payload, page: 1 }.with_indifferent_access, admin, account).perform
  end

  it "every shipped query is accepted by Chatwoot's filter and lists its open conversations only" do
    described_class::READY.each do |key, definition|
      attributes = definition[:priority] ? { priority: definition[:priority] } : {}
      matching, resolved, other = [:open, :resolved, :open].map { |status| create(:conversation, account: account, inbox: inbox, status: status) }
      [matching, resolved].each do |conversation|
        conversation.update!(attributes)
        conversation.update_labels([definition[:labels].first]) if definition[:labels]
      end
      # One more open conversation for each further label of the queue: any one of them lists it.
      also = definition[:labels].to_a.drop(1).map do |label|
        create(:conversation, account: account, inbox: inbox).tap { |conversation| conversation.update_labels([label]) }
      end

      result = filter(described_class.shipped_query(key)['payload'])

      expect(result[:conversations].map(&:id)).to match_array([matching.id] + also.map(&:id)), "queue #{key}"
      expect(described_class.count(queues.fetch(key), admin)).to eq(1 + also.size), "count of #{key}"
      [matching, resolved, other, *also].each(&:destroy!)
    end
  end

  # The SLA overview reads the conversations of a queue from the same run of
  # Chatwoot's filter (its unpaged relation): as many as the queue counts.
  it "the SLA overview finds every shipped queue's conversations where Chatwoot's filter counts them" do
    described_class::READY.each do |key, definition|
      listed = Array.new(2) { create(:conversation, account: account, inbox: inbox) }
      listed.each do |conversation|
        conversation.update!(priority: definition[:priority]) if definition[:priority]
        conversation.update_labels([definition[:labels].first]) if definition[:labels]
      end
      create(:conversation, account: account, inbox: inbox, status: :resolved).update_labels(definition[:labels].to_a.first(1))

      total, ids = Inclamo::TeamQueues::SlaOverview.listed(queues.fetch(key), admin)

      expect(total).to eq(described_class.count(queues.fetch(key), admin)), "count of #{key}"
      expect(ids).to match_array(listed.map(&:id)), "conversations of #{key}"
      listed.each(&:destroy!)
    end
  end

  it 'ships the queues on the labels the product already sets' do
    expect(described_class::READY.transform_values { |definition| definition[:labels] }).to eq(
      'urgent' => nil, 'ai_handover' => %w[inclamo_handover inclamo_error inclamo_limit], 'overdue' => %w[sla-overdue],
      'delivery' => %w[delivery inclamo_intent_delivery], 'cancellation' => %w[cancellation inclamo_intent_cancellation],
      'damage' => %w[damage inclamo_intent_damage], 'missing_parts' => %w[missing-parts inclamo_intent_missing_parts], 'return' => %w[return inclamo_intent_return]
    )
    expect(described_class::READY.values.flat_map { |definition| definition[:labels].to_a }).to all(match(/\A[a-z0-9_-]+\z/))
    expect(described_class.labels).to eq(%w[sla-overdue delivery cancellation damage missing-parts return])
  end

  it 'a label condition with several values lists a conversation with any one of them' do
    first, second = %w[delivery return].map do |label|
      create(:conversation, account: account, inbox: inbox).tap { |conversation| conversation.update_labels([label]) }
    end
    create(:conversation, account: account, inbox: inbox).update_labels(['damage'])
    payload = [described_class.condition('status', ['open'], 'and'), described_class.condition('labels', %w[delivery return])]

    expect(filter(payload)[:conversations].map(&:id)).to match_array([first.id, second.id])
  end

  it 'a misspelt filter key is refused' do
    payload = described_class.shipped_query('urgent')['payload'].map { |condition| condition.merge('attribute_key' => "#{condition['attribute_key']}x") }

    expect { filter(payload) }.to raise_error(CustomExceptions::CustomFilter::InvalidAttribute)
  end
end
