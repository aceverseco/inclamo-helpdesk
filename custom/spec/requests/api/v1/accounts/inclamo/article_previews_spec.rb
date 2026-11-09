# frozen_string_literal: true
require 'rails_helper'
RSpec.describe 'Protected help article previews', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:portal) { create(:portal, account: account) }
  let(:article) { create(:article, account: account, portal: portal, author: admin, status: :draft, content: 'Private draft words') }
  let(:public_path) { "/hc/#{portal.slug}/articles/#{article.slug}" }
  let(:preview_path) { "/api/v1/accounts/#{account.id}/inclamo/article_previews/#{article.id}" }
  before do
    allow(DomainHelper).to receive(:chatwoot_domain?).and_return(true)
    # The backend runner has no frontend toolchain; browser acceptance loads real assets.
    allow_any_instance_of(ActionView::Base).to receive(:vite_client_tag).and_return(''.html_safe)
    allow_any_instance_of(ActionView::Base).to receive(:vite_javascript_tag).and_return(''.html_safe)
  end

  it 'hides a direct draft while keeping published content public' do
    get public_path
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Private draft words')
    article.update!(status: :published)
    get public_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Private draft words')
  end

  it 'issues a scoped preview with no-store and no-referrer headers' do
    post preview_path, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    get response.parsed_body['url']
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Private draft words')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
  end

  it 'refuses absent authorization, another account, tampered and expired tokens' do
    post preview_path, as: :json
    expect(response).to have_http_status(:unauthorized)
    other = create(:user, account: create(:account), role: :administrator)
    post preview_path, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    post preview_path, headers: admin.create_new_auth_token, as: :json
    path = response.parsed_body['url']
    get "#{public_path}?preview_token=invalid"
    expect(response).to have_http_status(:not_found)
    travel 6.minutes do
      get path
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Private draft words')
    end
  end

  it 'cannot reuse a preview token for another article' do
    second = create(:article, account: account, portal: portal, author: admin, status: :draft)
    get "/hc/#{portal.slug}/articles/#{second.slug}", params: { preview_token: Inclamo::ArticlePreview.token(article) }
    expect(response).to have_http_status(:not_found)
  end
end
