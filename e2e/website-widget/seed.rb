# Synthetic website acceptance fixtures; never run against a merchant account.
raise 'Synthetic stack required' unless ENV['INCLAMO_SHOPIFY_BASE_URL'] == 'http://shopify-fixture:8080' && Account.find(1).name == 'Inclamo Theme Example'
a = Account.find(1)
inbox = a.inboxes.find(2)
admin = User.find_by!(email: 'theme-admin@example.test')
InboxMember.find_or_create_by!(inbox: inbox, user: admin)
portal = a.portals.first
article = portal.articles.find_or_initialize_by(title: 'Returns and exchanges')
article.assign_attributes(account: a, author: admin, locale: 'en', content: 'You can request a return within 30 days. This is a synthetic help article.', description: 'Synthetic return policy.', status: :published)
article.save!
# A local webhook fixture only; no requests leave this isolated Docker network.
bot = AgentBot.find_or_initialize_by(account: a, name: 'Synthetic website assistant')
bot.assign_attributes(outgoing_url: 'http://bot-fixture:8080/webhook', bot_type: 'webhook', bot_config: {})
bot.save!
puts({ portal_id: portal.id, article_id: article.id, bot_id: bot.id }.to_json)

empty = Account.find_or_create_by!(name: "Widget Empty Example")
AccountUser.find_or_create_by!(account: empty, user: admin) { |member| member.role = :administrator }
