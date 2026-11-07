## Context

See proposal.md. The AI service already renders each finished call once, for any helpdesk: entry, caller, line, end time, outcome, open or closed, priority, tags, a record with summary and requests, and the transcript; its Gorgias sink files that as a ticket. ADR 0068 puts the call in an API inbox "Phone" of this helpdesk, on the same contact as the chats, its turns as messages. `ai-agent-connection` creates the Phone inbox, the agent bot, its token and the labels; this change is what the helpdesk does with a call.

Facts checked in Chatwoot v4.19.1 (`build/chatwoot`):

- **A bot token reaches few endpoints.** After a token is authenticated (`app/controllers/concerns/access_token_auth_helper.rb:38-47`), Chatwoot's API base controller refuses an agent bot outside a fixed list (`app/controllers/api/base_controller.rb:6-7`, `access_token_auth_helper.rb:55-64`): conversation show, status, typing, priority, create, update and custom attributes; message create; assignment create; label index and create (`access_token_auth_helper.rb:2-7`). No contact endpoint is on the list.
- **Creating a conversation needs a contact.** `conversations#create` builds the conversation on a contact inbox made from `inbox_id` plus `contact_id`, or found by `source_id` (`app/controllers/api/v1/accounts/conversations_controller.rb:41-46`, `:207-229`); `ConversationBuilder` takes status, custom and additional attributes, assignee and team (`app/builders/conversation_builder.rb:20-39`) and reuses the last conversation only when the inbox locks to one (`:10-14`; `lock_to_single_conversation` defaults to false, `db/schema.rb:1355`).
- **Incoming messages can be written only in API inboxes** (`app/builders/messages/message_builder.rb:127-132`). A message can carry `external_created_at` (`message_builder.rb:139-141`, `app/models/message.rb:109-113`); whether the dashboard shows it is not yet read (task 1.10). Message content may be up to 150,000 characters (`message.rb:80`).
- **An incoming message reopens a resolved conversation** unless it is muted (`message.rb:414-421`).
- **Per-message notifications.** Each incoming or outgoing message that is not private notifies the conversation's assignee and participants (`app/models/concerns/message_filter_helpers.rb:16-18`, `app/services/messages/new_message_notification_service.rb:4-27`), deduplicated per message only (`:48-50`). The notification listener runs asynchronously (`app/dispatchers/async_dispatcher.rb:18`), so it reads the conversation as it is when the job runs, assignee included.
- **Outgoing messages are sent on by a job** (`message.rb:408-411`); for an API inbox that is its webhook URL (`app/models/channel/api.rb:11`), which the Phone inbox does not have.
- **Agent bot events go to the inbox's active bot and to a bot assignee only** (`app/listeners/agent_bot_listener.rb:36-43`, `:65-75`). A conversation in an inbox with an active bot starts `pending` (`app/models/conversation.rb:316-330`).
- **Auto-assignment** runs when a saved conversation changes to open (`app/models/concerns/auto_assignment_handler.rb:6-7`, `:15-22`); inboxes have it on by default (`db/schema.rb:1344`).
- **Contacts:** phone numbers are stored in E.164 (`app/models/contact.rb:54-56`, index on number and account `:36`); `identifier` is unique per account (`contact.rb:53`, `:39`).
- **Priority** has four levels, `low`, `medium`, `high`, `urgent` (`conversation.rb:87`). **Custom attribute definitions** exist for conversations, with display types including `link`, `date`, `number` and `list` (`app/models/custom_attribute_definition.rb:48-49`).
- **Token API access is on in CE** for every account (`app/models/account.rb:170-172`).
- The public Client API of an API inbox matches a contact by identifier, then email, then phone (`app/builders/contact_inbox_with_contact_builder.rb:67-74`).
- Seam 1 (`patches/0001-conversation-sidebar-sections.patch`) registers our sidebar sections; `sla-timers` adds an optional `visible(conversationId)` to its entries (branch `feat/sla-timers`, same patch).

## Goals / Non-Goals

**Goals:** one request per call, safe to repeat; the call on the caller's contact without guessing; turns readable as a chat; no message, notification storm or bot event caused by filing; no core patch.

**Non-Goals:** telephony and recordings; a stock-only path for a Chatwoot without our overlay; live calls; editing a filed call; merging contacts (Chatwoot's own merge does that).

## Decisions

**D1. One request to an endpoint of ours.** `POST /api/v1/accounts/:account_id/inclamo/calls`, under the overlay's routes, does the whole filing in one transaction. Alternatives rejected:
- *Stock API with the bot's token:* the bot cannot search or create contacts (facts above), so it cannot put the call on the caller's contact, and a call of sixty turns would be sixty-odd requests with no key to find the call again after a failure half way.
- *A user's token held by the AI service:* a person-shaped account with access to every contact, a seat in the team list, and still many requests per call.
- *The public Client API of the Phone inbox:* it matches by email before phone (opposite to our rule), one request per message, no key per call.
This is assumption 1 of the proposal: the chat path stays stock as ADR 0068 says; calls need our overlay.

**D2. Only the connection's bot.** Our controller inherits Chatwoot's API base controller, so the token is authenticated by Chatwoot; it skips `validate_bot_access_token!` and instead requires the authenticated resource to be the agent bot recorded on the account's connection, with the connection switched on. A user's token or another bot's token is unauthorised (401); no connection or a switched-off one is `not_connected` (409). Bots in Chatwoot can read any conversation of their account (`app/policies/conversation_policy.rb:10-11`, `:24-25`; `app/policies/inbox_policy.rb:22-24`); our endpoint writes only to the Phone inbox recorded on the connection.

**D3. The call's key.** Table `inclamo_call_conversations` (account, call id, conversation, contact, how matched, created at), unique on account and call id, written in the same transaction as the conversation. A repeat reads the row and answers 200 with `found: true`, changing nothing (assumption 8). Two filings at once: the second insert hits the unique index, its transaction rolls back, and it answers with the first row.

**D4. The contact rule runs in the helpdesk** (assumption 2), on exact E.164 phone and case-insensitive email, first match wins; two or more matches at either step mean a new contact plus `inclamo_match_ambiguous`. A new contact gets the identifier `inclamo:customer:<call id>`, the key the AI service already uses for profiles it makes. A found contact is never updated. The call uses the contact's contact inbox of the Phone inbox, created when missing.

**D5. Turns are written as records, the rest through Chatwoot's models.** In one transaction: the contact and contact inbox when new; the conversation with its final status, priority and custom attributes; the turns as message rows inserted without Chatwoot's message callbacks (caller turns incoming from the contact, agent turns outgoing from the connection's bot, `status: sent`, content and processed content set, dated by each turn's time, or one second apart ending at the call's end when the AI service sends none); then the record as a private note through the model; then the labels; then our key row. Why the turns skip the callbacks: with them, every turn would queue a notification job that finds the assignee already set by auto-assignment (facts above), outgoing turns would queue send jobs, an incoming turn would reopen a resolved call, and the merchant's rules would run once per turn. Without them, Chatwoot's events still run for the new conversation, its assignment, its status and its note, as for a chat. What this gives up: the merchant's webhooks and automation rules see the call's conversation and its record note, not each turn (risks). The Phone inbox has no bot, so the conversation does not start `pending` and no bot event fires.

**D6. The card reads the conversation's custom attributes.** `inclamo_call_entry`, `inclamo_call_line`, `inclamo_call_caller`, `inclamo_call_duration` (seconds), `inclamo_call_ended_at`, `inclamo_call_outcome`, `inclamo_call_matched_by`, `inclamo_call_recording`. The endpoint writes them; this change defines them in the account at connection, as one more step of the connection of `ai-agent-connection` (assumption 4), so filters and rules can use them; the card reads them whether defined or not. The card is an entry of seam 1 with `visible(conversationId)` true when the conversation has `inclamo_call_outcome`. It uses the `visible` hook of `sla-timers`; if that change is not merged first, this change carries the same hook in patch 0001, word for word, so no second seam appears. Outcomes the card does not know are shown by their value, so a new outcome of the AI service needs no release of the helpdesk.

**D7. Masking before storing** (assumption 7): runs of 13 to 19 digits, spaces or dashes allowed between them, that pass the Luhn check, in turns, the record and the caller's name, become `[card number removed]`.

**D8. Validation and refusals.** `call_id` required, up to 100 characters of letters, digits, `_ : . -`; `entry` one of `inbound`, `outbound`, `web`; numbers in E.164 or absent; `ended_at` ISO 8601; `duration` a whole number of seconds or absent; `priority` one of Chatwoot's four or absent; labels at most 20, each `inclamo_` plus lowercase letters, digits or underscores; `recording_url` https only; at most 500 turns, a turn at most 10,000 characters, the record at most 8,000. Codes: `invalid_call` (shape), `invalid_label`, `too_large`, `not_connected`. A refusal never echoes the call's content, and the log keeps the call id, the code and counts only.

**D9. The answer.** 201 for a new call and 200 for a repeat, both with `conversation_id` (the display number), `contact_id`, `found`, `matched_by` (`phone`, `email`, `created`, `anonymous`, `ambiguous`) and `labels_added`. The fields mirror what the AI service's sinks already report, so its journal needs no new words.

**D10. The contract document.** `docs/ai-connector-calls.md` holds the request, the answer, the rule and the codes for the AI service's side; `docs/ai-connector.md` (from `ai-agent-connection`) links it. It is drafted with this change and marked as proposed until the change is approved.

**D11. End-to-end through a stand-in agent.** A small test service in `e2e/` holds the connection's bot token made in the test setup, files calls from invented fixtures (`e2e/fixtures/calls/*.json`, numbers 555-01xx, addresses at `example.com`), and records every agent bot event it receives, so the tests can show that filing wakes no agent. It is the same stand-in `ai-agent-connection` uses for chats; this change adds the call fixtures and the filing step.

## Risks / Trade-offs

- [Turns are inserted without Chatwoot's callbacks; a Chatwoot release may add a field that callbacks fill] → a backend spec writes a turn our way and reads it back through Chatwoot's own messages endpoint; the upgrade routine of spec-plan §5 runs it.
- [The merchant's webhooks and rules do not see individual turns] → the record note and the conversation events do reach them; stated in the merchant docs.
- [Calls need our overlay, unlike chats] → assumption 1; a stock path in the AI service can come later if the AI is sold to merchants on another Chatwoot.
- [Ambiguous contacts multiply] → the label lists them; Chatwoot's contact merge joins them.
- [Turn times come from the AI service's clock] → shown as sent; missing times keep the order and end at the call's end.
- [A bot token can act on every conversation of its account] → Chatwoot's own model, not new here; the AI service keeps the token as a secret (ai-agent-connection).

## Migration Plan

One migration in `custom/db/migrate` for the key table, with a version no other change uses (check every worktree's migrate directory first). Rollback: remove the endpoint and the card entry and drop the table; filed calls stay as ordinary conversations with their messages and attributes.

## Open Questions

- Whether the recording link points to the AI service's call card or to an audio file is the AI service's choice; the card shows a link either way.
