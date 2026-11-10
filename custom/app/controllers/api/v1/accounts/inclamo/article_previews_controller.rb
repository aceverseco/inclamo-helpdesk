# frozen_string_literal: true

class Api::V1::Accounts::Inclamo::ArticlePreviewsController < Api::V1::Accounts::BaseController
  def create
    article = Current.account.articles.find(params[:id])
    authorize article.portal, :show?
    token = ::Inclamo::ArticlePreview.token(article)
    response.headers['Cache-Control'] = 'private, no-store'
    render json: { url: "/hc/#{article.portal.slug}/articles/#{article.slug}?preview_token=#{ERB::Util.url_encode(token)}" }
  end
end
