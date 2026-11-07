## Why

The helpdesk is the front door for the AI agent (ADR 0063): with a subscription, the agent answers first in the merchant's inboxes and hands over to the team. Nothing connects the two today. ADR 0068 settles how they meet: Chatwoot's own agent bot, events by a signed webhook, actions through Chatwoot's API. This change is the helpdesk's side of that link for chat (slice 5 of `docs/spec-plan.md`), written so the AI service can be built against a stated contract while the helpdesk side is built and tested on its own.

## What Changes

- An **"AI agent" page** in the account settings, for administrators. Without a connection it is the door of 0063: what the agent does, how to get it, a field for a connection code. With a connection: the connected inboxes, the state (connected, failing, disconnected), when the agent last answered, the last delivery error, and "Disconnect".
- **Connecting with a code issued by the AI service.** The helpdesk creates a Chatwoot agent bot, registers it with the AI service (the bot's token and secret, the inboxes, the account), points the bot at the address the AI service returns, attaches it to the inboxes the administrator picked, and creates an API inbox "Phone" and the agent's labels. When the AI service refuses, nothing is left behind.
- **The agent answers first.** A new conversation in a connected inbox is Pending while the agent handles it, as Chatwoot does for any bot. It becomes Open when the agent hands it over, when a person of the team replies publicly or is assigned, and when the AI service cannot be reached.
- **Two narrow endpoints for the agent**, authenticated by the bot's token and limited to the connected inboxes. One reads a conversation's public messages with their files and the number of files the shopper sent; Chatwoot does not let a bot read messages. The other adds labels without dropping the team's; Chatwoot's own label call replaces them all. Labels starting with `inclamo_` that the account lacks are created there, so labels the agent adds per request type are shown.
- **Delivery health recorded** per connection: every webhook to the AI service is recorded as delivered or failed, so the page can say the agent is failing before a merchant notices.
- **Disconnect**: the agent's pending conversations go to the team, the bot and its token are removed, the AI service is told. The "Phone" inbox, its conversations and the labels stay.
- **The contract document** `docs/ai-connector.md` for whoever builds the AI service's side: events, fields, calls, labels, handover, errors, retries, limits.
- **A stand-in agent** in `e2e/` that implements the contract, so every scenario runs end to end without the AI service; the same flows can later run against it.
- No new seam in Chatwoot's dashboard: the page uses the settings-pages seam (patch 0002). One core class is extended from the overlay: the webhook sender, to record deliveries.

Not in this change: subscription and billing (the AI service's), the greyed "Summarise" and "Draft reply" buttons and the usage counter (slice 6), calls as conversations (`call-conversations`), an MCP server (ADR 0068, slice 10), more than one agent per account, the agent in an inbox that already has another bot.

## Capabilities

### New Capabilities
- `ai-agent-connection`: how an account connects to and disconnects from the AI agent, what the team and the agent see while the agent handles a conversation, when a conversation goes to the team, and what the helpdesk gives the agent to read and to label.

### Modified Capabilities
- none.

## Assumptions for the founder

> Founder, 2026-11-07: assumption 4 accepted, «Пока А» (the bot's token and our endpoints, not a user's token). The founder asked for the changes to be built in turn without further stops; the other assumptions stand as written until the founder says otherwise.

1. **Pairing by a connection code** that the AI service issues to a subscribed merchant; the administrator pastes it once. The shape of the AI service's registration call (`POST {service}/connections`, `DELETE {service}/connections/{id}`, fields in `design.md` D3) is a proposal to agree with the builder of the AI service.
2. **The bot is not attached to "Phone".** Calls are posted there after they end (`call-conversations`); the agent takes no turns in that inbox.
3. **Pending while the agent handles, Open when the team has it.** That is Chatwoot's own behaviour for bot inboxes, and the team will look for the agent's conversations under Pending. A person's public reply or assignment also moves a pending conversation to Open (Chatwoot's Community Edition does not do this by itself). A resolved conversation the shopper writes in again goes back to the agent, as Chatwoot does.
4. **The agent reads history through our endpoint**, public messages only, not private notes: Chatwoot keeps its message list closed to bots, and opening it would also show the team's notes.
5. **The agent adds only `inclamo_` labels**, through our endpoint, which keeps every label the team set. The fixed set the AI service uses today is created at connection with descriptions; any other `inclamo_` label is created the first time the agent adds it.
6. **When the AI service cannot take an event, the conversation goes to the team** at once, by Chatwoot's own rule; the connection turns off the account setting that would keep it waiting.
7. **Inboxes that already have another bot cannot be picked**, rather than replacing that bot.
8. **Disconnecting hands the agent's pending conversations to the team** and keeps "Phone" and the labels.

## Impact

- Backend: one table (`inclamo_ai_connections`), a connect and a disconnect service, a registration client, an administrators' endpoint, two endpoints for the bot, a listener (a person's reply or assignment opens a pending conversation) and a delivery recorder over Chatwoot's webhook sender.
- Dashboard: the "AI agent" page through the settings-pages seam; no new patch.
- Outbound traffic: the helpdesk calls the AI service's registration address and Chatwoot posts events to it; both go through Chatwoot's SSRF filter, so the AI service must be public over HTTPS.
- Requires Chatwoot's encryption keys (the bot's secret is stored encrypted), as the store connection already does.
- Tests: backend specs, component tests, a stand-in agent, end-to-end tests for every scenario in the widget and the dashboard.
