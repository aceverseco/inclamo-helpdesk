# frozen_string_literal: true

require 'rails_helper'

# The instance reports nothing about itself to Chatwoot's hub. Every outgoing
# request is refused here (localhost included), so one that was attempted
# fails the example by itself, before the count below is read.
RSpec.describe "Nothing is reported to Chatwoot's hub", type: :request do
  let(:onboarding_flag) { Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING }

  around do |example|
    WebMock.disable_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after { Redis::Alfred.delete(onboarding_flag) }

  def expect_no_request
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'answers the three calls of the hub client itself' do
    %i[sync_with_hub register_instance emit_event].each do |name|
      expect(ChatwootHub.method(name).owner).to eq(Inclamo::QuietHub)
    end
  end

  it "stands in front of a method of Chatwoot's that does call the hub" do
    stub_request(:post, ChatwootHub.ping_url).to_return(status: 200, body: '{}')

    ChatwootHub.method(:sync_with_hub).super_method.call

    expect(a_request(:post, ChatwootHub.ping_url)).to have_been_made.once
  end

  it 'runs the daily jobs of a production instance without a request' do
    allow(Rails.env).to receive(:production?).and_return(true)

    with_modified_env DISABLE_TELEMETRY: nil do
      expect { Internal::TriggerDailyScheduledItemsJob.perform_now }.to have_enqueued_job(Internal::CheckNewVersionsJob)
      expect { Internal::CheckNewVersionsJob.perform_now }.not_to raise_error
    end

    expect_no_request
  end

  it 'sends no event, with telemetry left on' do
    with_modified_env DISABLE_TELEMETRY: nil do
      expect(ChatwootHub.emit_event('synthetic_event', { 'synthetic' => true })).to be_nil
    end

    expect_no_request
  end

  it 'completes onboarding with "subscribe to updates" ticked without a request' do
    Redis::Alfred.set(onboarding_flag, true)

    post '/installation/onboarding', params: {
      subscribe_to_updates: 'true',
      user: { name: 'Synthetic Owner', company: 'Synthetic Store', email: 'owner@example.test', password: 'Synthetic-Passw0rd!' }
    }

    expect(response).to redirect_to('/')
    expect(flash[:error]).to be_nil
    expect(Redis::Alfred.get(onboarding_flag)).to be_nil
    expect(User.find_by(email: 'owner@example.test')).to be_a(SuperAdmin)
    expect_no_request
  end
end
