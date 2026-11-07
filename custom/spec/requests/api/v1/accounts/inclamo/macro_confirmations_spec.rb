# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo macro confirmations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:other) { create(:conversation, account: account, inbox: inbox) }
  let(:refund) { macro_with('inclamo_refund_full', 'send_message') }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def macro_with(*names, visibility: :global, by: admin)
    create(:macro, account: account, created_by: by, visibility: visibility,
                   actions: names.map { |name| { 'action_name' => name, 'action_params' => name == 'send_message' ? ['Sorry'] : [] } })
  end

  # The agent's "Run" in the dialog, for the macro as the preview showed it.
  def confirm(macro, digest: Inclamo::Shopify::MacroSteps.digest(macro), user: agent)
    post "/api/v1/accounts/#{account.id}/inclamo/macro_confirmations",
         params: { macro_id: macro.id, conversation_id: conversation.display_id, digest: digest }, headers: user.create_new_auth_token, as: :json
  end

  # Chatwoot's own request that runs a macro; signed in, as the dashboard sends it.
  def execute(macro, ids = [conversation.display_id], headers: agent.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/macros/#{macro.id}/execute", params: { conversation_ids: ids }, headers: headers, as: :json
  end

  it 'runs a macro with order steps from the dashboard after the agent confirmed it, once per confirmation' do
    confirm(refund)
    expect(response).to have_http_status(:no_content)

    expect { execute(refund) }.to have_enqueued_job(MacrosExecutionJob)
    expect(response).to have_http_status(:ok)

    expect { execute(refund) }.not_to have_enqueued_job(MacrosExecutionJob)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('not_confirmed')
  end

  it 'runs nothing of a macro with order steps that the dashboard did not confirm, as from a page holding an older copy of it' do
    expect { execute(refund) }.not_to have_enqueued_job(MacrosExecutionJob)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'not_confirmed')
    expect(response.parsed_body['message']).to include('no step of it ran')
  end

  it 'holds a confirmation only for the macro as the agent saw it' do
    seen = Inclamo::Shopify::MacroSteps.digest(refund)
    confirm(refund)
    refund.update!(actions: refund.actions + [{ 'action_name' => 'inclamo_cancel_order', 'action_params' => [] }])

    expect { execute(refund) }.not_to have_enqueued_job(MacrosExecutionJob)

    confirm(refund, digest: seen)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('macro_changed')
  end

  it 'holds a confirmation only for its conversation and its agent' do
    confirm(refund)

    expect { execute(refund, [other.display_id]) }.not_to have_enqueued_job(MacrosExecutionJob)
    expect { execute(refund, headers: admin.create_new_auth_token) }.not_to have_enqueued_job(MacrosExecutionJob)
    expect { execute(refund) }.to have_enqueued_job(MacrosExecutionJob)
  end

  it 'runs a macro with order steps in one conversation at a time from the dashboard' do
    confirm(refund)

    expect { execute(refund, [conversation.display_id, other.display_id]) }.not_to have_enqueued_job(MacrosExecutionJob)
    expect(response.parsed_body['error']).to eq('one_at_a_time')
  end

  it 'runs a macro without order steps as before, without a confirmation' do
    expect { execute(macro_with('send_message'), [conversation.display_id, other.display_id]) }.to have_enqueued_job(MacrosExecutionJob)
    expect(response).to have_http_status(:ok)
  end

  it 'asks no confirmation of a run through the API with an access token, which has no dialog' do
    expect { execute(refund, [conversation.display_id, other.display_id], headers: { api_access_token: agent.access_token.token }) }
      .to have_enqueued_job(MacrosExecutionJob)
    expect(response).to have_http_status(:ok)
  end

  it 'is refused for a personal macro of somebody else' do
    confirm(macro_with('inclamo_refund_full', visibility: :personal))

    expect(response).to have_http_status(:unauthorized)
  end
end
