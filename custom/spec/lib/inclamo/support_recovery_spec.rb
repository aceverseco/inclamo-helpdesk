# frozen_string_literal: true

require 'rails_helper'

# How the support transport and jobs come back from failures that are not the
# author's doing: a refused or unreachable support endpoint, an event the
# installation cannot import and a notification that can no longer be sent.
RSpec.describe 'Support recovery from failures' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account: account, role: :agent) }
  let(:member) { AccountUser.find_by!(account: account, user: author) }
  let(:local) do
    Inclamo::Support::LocalRequests.new(member)
                                   .create!('uuid' => SecureRandom.uuid, 'category' => 'question', 'body' => 'Synthetic issue', 'files' => [])
  end
  let(:endpoint) { 'https://support.example.test/inclamo/support/v1' }
  let(:installation) { Inclamo::Support::Installation.identity.tap { |record| record.update!(source_id: SecureRandom.uuid, endpoint: endpoint) } }

  around do |example|
    with_modified_env(INCLAMO_SUPPORT_ENDPOINT: endpoint) { example.run }
  end

  describe 'delivering a submission' do
    let(:submission) { local.submissions.first }

    before { installation }

    [401, 403, 404].each do |status|
      it "keeps it queued when central intake answers #{status}, as when intake is halted" do
        stub_request(:post, "#{endpoint}/submissions").to_return(status: status)

        Inclamo::Support::DeliverJob.perform_now(submission.id)

        expect(submission.reload).to have_attributes(state: 'queued', error_code: 'support_unavailable', lease_until: nil)
        expect(submission.next_attempt_at).to be_future
      end
    end

    it 'delivers it once intake answers again' do
      stub_request(:post, "#{endpoint}/submissions")
        .to_return({ status: 404 }, { status: 200, body: { reference: SecureRandom.uuid, message_id: '5', state: 'delivered' }.to_json })

      Inclamo::Support::DeliverJob.perform_now(submission.id)
      submission.reload.update!(next_attempt_at: nil)
      Inclamo::Support::DeliverJob.perform_now(submission.id)

      expect(submission.reload).to have_attributes(state: 'delivered', central_message_id: '5')
    end

    it 'still fails it when the author no longer belongs to the account' do
      submission
      member.destroy!

      Inclamo::Support::DeliverJob.perform_now(submission.id)

      expect(submission.reload).to have_attributes(state: 'failed', error_code: 'access_changed')
      expect(a_request(:post, "#{endpoint}/submissions")).not_to have_been_made
    end
  end

  it 'reports a support endpoint whose name does not resolve as unavailable' do
    installation
    stub_request(:get, "#{endpoint}/events?cursor=0").to_raise(SocketError.new('getaddrinfo: Name or service not known'))

    expect { Inclamo::Support::Transport.new.events(0) }.to raise_error(Inclamo::Support::Unavailable)
  end

  it 'passes over events it cannot import and still imports the later ones' do
    installation
    local.update!(central_reference: 'central-a')
    reply = { 'kind' => 'message', 'request_reference' => local.reference, 'central_reference' => 'central-a', 'direction' => 'support',
              'actor' => { 'name' => 'Support', 'administrator' => false }, 'sent_at' => Time.current.iso8601, 'files' => [] }
    events = [reply.merge('id' => 6), # no message id
              reply.merge('id' => 7, 'message_id' => '70', 'central_reference' => 'central-b', 'body' => 'Another request'),
              reply.merge('id' => 8, 'message_id' => '80', 'body' => 'Public answer')]
    stub_request(:post, "#{endpoint}/recipients").to_return(status: 200, body: '{}')
    stub_request(:get, "#{endpoint}/events?cursor=0").to_return(status: 200, body: { events: events, cursor: 8, more: false }.to_json)

    Inclamo::Support::SyncJob.perform_now

    expect(installation.reload).to have_attributes(cursor: 8, failures: 0)
    expect(local.messages.pluck(:central_message_id, :body)).to eq([['80', 'Public answer']])
  end
end
