# frozen_string_literal: true

module Inclamo
  module ArticlePreview
    PURPOSE = 'inclamo-article-preview'

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def self.token(article)
      verifier.generate({ 'id' => article.id, 'account_id' => article.account_id }, purpose: PURPOSE, expires_in: 5.minutes)
    end

    module PublicGuard
      private

      def set_article
        super
        token = params[:preview_token]
        proof = ArticlePreview.verifier.verified(token, purpose: ArticlePreview::PURPOSE) if token.present?
        preview = proof == { 'id' => @article.id, 'account_id' => @article.account_id }
        return head :not_found unless @article.published? || preview
        return unless preview

        response.headers['Cache-Control'] = 'private, no-store'
        response.headers['Referrer-Policy'] = 'no-referrer'
        @article.title = @article.draft_title if @article.draft_title.present?
        @article.content = @article.draft_content unless @article.draft_content.nil?
      end
    end
  end
end
