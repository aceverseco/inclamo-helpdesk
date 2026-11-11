# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Website widget configuration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: build(:channel_widget, account: account, widget_color: '#1f93ff')) }
  let(:url) { "/api/v1/accounts/#{account.id}/inclamo/website_widgets/#{inbox.id}" }
  let(:headers) { admin.create_new_auth_token }

  def read_config
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    response.parsed_body
  end

  def publish(config, changes = {})
    patch url, headers: headers, params: { configuration: { revision: config['revision'], settings: config['settings'], native: config['native'] }.merge(changes) }, as: :json
  end

  it 'publishes shared native and launcher settings, and rejects stale saves' do
    config = read_config
    config['settings']['position'] = 'left'
    config['native']['widget_color'] = '#123456'
    publish(config)
    expect(response).to have_http_status(:ok), response.body
    expect(inbox.channel.reload.widget_color).to eq('#123456')
    expect(read_config.dig('settings', 'position')).to eq('left')
    publish(config)
    expect(response).to have_http_status(:conflict)
  end

  it 'detects edits through the original native inbox page' do
    config = read_config
    inbox.channel.update!(welcome_title: 'Changed elsewhere')
    publish(config)
    expect(response).to have_http_status(:conflict)
    expect(read_config.dig('native', 'welcome_title')).to eq('Changed elsewhere')
  end

  it 'does not mistake background attachment processing for a competing publication' do
    publish(read_config)
    config = response.parsed_body
    inbox.touch
    Inclamo::WebsiteWidget.find_by!(inbox: inbox).touch
    publish(config)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['revision']).not_to eq(config['revision'])
  end

  it 'keeps all published values unchanged when a home action is invalid' do
    config = read_config
    color = inbox.channel.widget_color
    config['native']['widget_color'] = '#123456'
    config['settings']['links'] = [{id:'bad',label:'Unsafe',enabled:true,kind:'url',url:'javascript:alert(1)'}]
    publish(config)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(inbox.channel.reload.widget_color).to eq(color)
    expect(Inclamo::WebsiteWidget.where(inbox: inbox)).not_to exist
  end

  it 'bounds settings and enforces role and account ownership' do
    config = read_config
    config['settings']['offset_x'] = 900
    publish(config)
    expect(response).to have_http_status(:unprocessable_entity)
    agent = create(:user, account: account, role: :agent)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    foreign = create(:inbox)
    get "/api/v1/accounts/#{account.id}/inclamo/website_widgets/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects active SVG and accepts a safe custom icon without changing header identity' do
    config = read_config
    unsafe = Base64.strict_encode64('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
    publish(config, 'icon_image' => { 'data' => unsafe })
    expect(response).to have_http_status(:unprocessable_entity)
    safe = Base64.strict_encode64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" fill="#123456"/></svg>')
    config['settings']['icon'] = 'custom'
    publish(config, 'icon_image' => { 'data' => safe })
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['icon_url']).to be_present
    expect(inbox.reload.avatar).not_to be_attached
    icon_url = response.parsed_body['icon_url']
    get icon_url
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/svg+xml')
    expect(response.headers['Content-Security-Policy']).to include('sandbox')
    blob = Inclamo::WebsiteWidget.find_by!(inbox: inbox).launcher_image.blob
    get "/inclamo/widget-images/#{blob.signed_id}"
    expect(response).to have_http_status(:not_found)
    blob.update!(metadata: {})
    get icon_url
    expect(response).to have_http_status(:not_found)
  end

  it 'shares a native raster header logo and rejects unsupported header formats atomically' do
    config = read_config
    image = Vips::Image.black(24, 24).write_to_buffer('.png')
    publish(config, 'avatar_image' => { 'data' => Base64.strict_encode64(image) })
    expect(response).to have_http_status(:ok), response.body
    expect(inbox.reload.avatar).to be_attached
    expect(response.parsed_body['avatar_url']).to be_present
    original = inbox.avatar.blob_id
    config = read_config
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>'
    publish(config, 'avatar_image' => { 'data' => Base64.strict_encode64(svg) })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(inbox.reload.avatar.blob_id).to eq(original)
  end

  it 'renders an authenticated preview without creating a visitor or conversation' do
    expect { get "#{url}/preview", headers: headers }.not_to change(Contact, :count)
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to include('inclamoWidgetPreview', 'inclamo-widget-preview')
    expect(response.body).not_to include(inbox.channel.hmac_token)
  end

  it 'serializes hostile starter text safely without exposing secrets' do
    config = read_config
    text = '</script><script>alert(1)</script>'
    config['settings']['starters'] = [{id:'s1',enabled:true,label:'Question',message:text}]
    config['native']['welcome_title'] = text
    config['native']['name'] = "Example's store"
    publish(config)
    expect(response).to have_http_status(:ok), response.body
    public_value = Inclamo::WebsiteWidget.for_public(inbox)
    expect(public_value['starters'].first['message']).to eq(text)
    expect(public_value.to_json).not_to include(inbox.channel.hmac_token)
    get '/widget', params: { website_token: inbox.channel.website_token }
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to include('\\u003c/script\\u003e')
    expect(response.body).not_to include(text)
  end

  it 'validates a portal switch and new article link as one publication' do
    publish(read_config)
    config = response.parsed_body
    portal = create(:portal, account: account)
    article = create(:article, account: account, portal: portal, status: :published)
    config['native']['portal_id'] = portal.id
    config['settings']['links'] = [{ id: 'new-portal', label: 'New help center', enabled: true, kind: 'article', article_id: article.id }]
    publish(config)
    expect(response).to have_http_status(:ok), response.body
    expect(inbox.reload.portal_id).to eq(portal.id)
    expect(response.parsed_body.dig('public', 'links', 0, 'url')).to include(portal.slug)
  end

  it 'omits an article that becomes unavailable without losing the launcher settings' do
    portal = create(:portal, account: account)
    article = create(:article, account: account, portal: portal, status: :published)
    inbox.update!(portal: portal)
    config = read_config
    config['settings']['position']='left'
    config['settings']['links']=[{id:'article',label:'Help',enabled:true,kind:'article',article_id:article.id}]
    publish(config)
    expect(response).to have_http_status(:ok), response.body
    article.update!(status: :archived)
    public_value = Inclamo::WebsiteWidget.for_public(inbox.reload)
    expect(public_value['links']).to eq([])
    expect(public_value['position']).to eq('left')
  end

  it 'validates raster content, dimensions and size and preserves the previous icon after rejection' do
    config = read_config
    %w[png jpg webp].each do |extension|
      bytes = Vips::Image.black(24, 24).write_to_buffer(".#{extension}")
      config['settings']['icon'] = 'custom'
      publish(config, 'icon_image' => { 'data' => Base64.strict_encode64(bytes) })
      expect(response).to have_http_status(:ok), response.body
      config = response.parsed_body
    end
    original = config['icon_url']
    bad_images = [
      'not an image', "\x89PNG\r\n\x1a\n".b,
      'x' * 1_048_577,
      Vips::Image.black(4097, 1).write_to_buffer('.png'),
      '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.test/x"/></svg>',
      '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>',
      '<svg><path fill="url(https://example.test/x)"/></svg>',
      '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg>&x;</svg>',
      '<svg><path></svg>'
    ]
    bad_images.each do |bytes|
      publish(config, 'icon_image' => { 'data' => Base64.strict_encode64(bytes) })
      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(read_config['icon_url']).to eq(original)
    end
    publish(config, 'remove_icon' => true)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['icon_url']).to be_nil
  end

  it 'bounds home actions, paths and ids without publishing invalid records' do
    config = read_config
    starter = {'id' => 'one', 'label' => 'Help', 'message' => 'Hello', 'enabled' => true}
    invalid = [
      {'starters' => [starter, starter]},
      {'starters' => 7.times.map { |i| starter.merge('id' => i.to_s) }},
      {'starters' => [starter.merge('label' => 'x' * 61)]},
      {'starters' => [starter.merge('message' => 'x' * 501)]},
      {'visibility' => {'mode' => 'include', 'rules' => []}},
      {'visibility' => {'mode' => 'exclude', 'rules' => [{'path' => '/cart?q=x', 'match' => 'exact'}]}},
      {'links' => [{'id' => 'l1', 'enabled' => true, 'label' => 'Bad', 'kind' => 'url', 'url' => 'https://user:password@example.test'}]},
      {'callback_url' => 'https://example.test'}
    ]
    invalid.each do |settings|
      publish(config, 'settings' => config['settings'].merge(settings))
      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(Inclamo::WebsiteWidget.where(inbox: inbox)).not_to exist
    end
    settings = config['settings'].merge('starters' => 7.times.map { |i| starter.merge('id' => i.to_s, 'enabled' => i < 6) })
    publish(config, 'settings' => settings)
    expect(response).to have_http_status(:ok), response.body
    expect(Inclamo::WebsiteWidget.for_public(inbox)['starters'].size).to eq(6)
  end

  it 'preserves native fallback and prevents non-website or foreign-account records' do
    expect(Inclamo::WebsiteWidget.for_public(inbox)).to eq({})
    native = create(:inbox, account: account, channel: create(:channel_api, account: account))
    get "/api/v1/accounts/#{account.id}/inclamo/website_widgets/#{native.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    record = Inclamo::WebsiteWidget.new(account: create(:account), inbox: inbox)
    expect(record).not_to be_valid
    record = Inclamo::WebsiteWidget.create!(account: account, inbox: inbox, settings: {})
    expect(record.public_config['offset_x']).to eq(20)
    record.update_column(:settings, {'theme' => 'invalid'})
    expect(Inclamo::WebsiteWidget.for_public(inbox)).to eq({})
    get "#{url}/preview"
    expect(response).to have_http_status(:unauthorized)
  end

end
