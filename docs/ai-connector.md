# AI connector contract, version 1

How an AI service (chat and voice agent) works with this helpdesk. The helpdesk
is Chatwoot Community Edition with our overlay; the AI service is a separate
product. The helpdesk delivers events and offers a few calls; everything the
agent decides is the AI service's.

Version 1. Source references are for Chatwoot v4.19.1, with paths relative
to its tree; `custom/` is the overlay. External AI services implement the
registration interface in §1.2. Finished-call ingestion is not implemented
in this revision.

```
 Shopper (widget)        Helpdesk                                 AI service
 ────────────────        ────────                                 ──────────
 message ──────────▶  conversation Pending, agent bot attached
                          │  agent-bot webhook, signed (§2)
                          └──────────────────────────────────▶  answers 200 at once,
                                                                 then runs the turn
                      ◀── note, priority, hand over (§4)        ──
                      ◀── protected reply, history and files,  ──
                          labels (§5)
 call (phone) ─────────────────────────────────────────────────▶ voice agent
```

## 1. Connecting

### 1.1 The connection code

The AI service issues a code the merchant's administrator pastes on the
helpdesk's **Settings → AI agent** page:

```
aic1.<base64url of {"service_url": "https://…", "token": "…"}>
```

`service_url` is HTTPS (HTTP is accepted only on a test stack that allows
private networks). `token` is one-time and short-lived; its lifetime is the AI
service's choice. A code that does not decode, or a URL that is not HTTPS, is
refused before any request.

The administrator also picks the inboxes the agent answers in. An inbox that
already has another bot or a Dialogflow integration cannot be picked (Chatwoot
allows one bot per inbox, `app/models/inbox.rb:76-77`).

### 1.2 Registration

The helpdesk creates the agent bot (with no webhook yet) and the **Phone** API
inbox, then calls:

```
POST {service_url}/connections
Authorization: Bearer {token}
Content-Type: application/json

{
  "contract": 1,
  "helpdesk_url": "https://helpdesk.example.com",
  "account": { "id": 1, "name": "Shop" },
  "bot": { "id": 7, "access_token": "…", "secret": "…" },
  "phone_inbox_id": 12,
  "inbox_ids": [3, 5]
}
```

| Answer | Meaning |
| --- | --- |
| `201 { "connection_id": "…", "webhook_url": "https://…" }` | connected: the helpdesk sets the bot's webhook to `webhook_url`, attaches the bot to `inbox_ids`, creates the labels of §6 |
| `4xx { "error": "…", "message": "…" }` | refused: `message` is shown to the administrator; the bot and a new Phone inbox are removed |
| anything else, or nothing within 10 s | "the AI service did not answer"; nothing is left behind |

Keep `bot.access_token` and `bot.secret` as secrets: the token acts in the
account, the secret checks the signature of every event.

`connection_id` is a string (or a number) of at most 200 characters, and
`webhook_url` an HTTPS address of at most 2000. A `201` without them is taken
as no answer; when it carried a `connection_id`, the helpdesk asks, best
effort, to remove it (§1.3). Redirects are not followed. Both calls go through
Chatwoot's SSRF filter, so `service_url` and `webhook_url` must be public
(`lib/safe_fetch.rb`); `helpdesk_url` is the installation's `FRONTEND_URL`.

### 1.3 Disconnecting

The administrator presses **Disconnect**. The helpdesk moves every Pending
conversation of the connected inboxes to the team (Open), detaches the bot,
destroys its token and the bot, then calls, best effort:

```
DELETE {service_url}/connections/{connection_id}
Authorization: Bearer {the bot's former access token}
```

Any `2xx` counts as told; anything else is shown on the AI agent page ("the
AI service could not be told"). The Phone inbox, its conversations and the
labels stay. The token is refused from that moment: a call with it answers
`401`.

## 2. Events

### 2.1 Delivery

Each event is one `POST {webhook_url}` with a JSON body (`lib/webhooks/trigger.rb`):

| Header | Value |
| --- | --- |
| `X-Chatwoot-Timestamp` | Unix time of the delivery |
| `X-Chatwoot-Signature` | `sha256=` + hex HMAC-SHA256 of `"{timestamp}.{raw body}"` with `bot.secret` (lines 54-63) |
| `X-Chatwoot-Delivery` | a UUID per event, the same on its retries |

The AI service SHALL:
- check the signature over the raw body and refuse a timestamp older than five
  minutes;
- drop a delivery id it has seen;
- **answer `200` at once and run the turn after.** The helpdesk waits 5 s
  (`WEBHOOK_TIMEOUT`, lines 118-123).

Only `429` and `500` are retried: three attempts, three seconds apart (line 3,
lines 125-127). Any other failure (another status, a timeout, no connection)
ends the delivery, and **a Pending conversation goes to the team** (Open, with
Chatwoot's activity message, lines 65-89; the helpdesk keeps the account
setting `keep_pending_on_bot_failure` off). The helpdesk shows the last
delivery and the last failure on the AI agent page.

### 2.2 Which events, which to act on

The bot gets `message_created` and `message_updated` for every incoming,
outgoing or template message of its inboxes, whatever the conversation's
status (`app/listeners/agent_bot_listener.rb`,
`app/models/concerns/message_filter_helpers.rb:8-10`): the shopper's, its own
replies, the team's replies **and the team's private notes**. It also gets
`conversation_opened`, `conversation_resolved`, `conversation_status_changed`,
`conversation_updated` and `webwidget_triggered`.

Take a turn only for a `message_created` where:
- `message_type` is `incoming` (only the shopper's messages are; the
  contact in `sender` carries no `type`);
- `private` is `false`;
- `conversation.status` is `pending`;
- `conversation.inbox_id` is one of the connected inboxes.

Ignore everything else for turns: your own replies come back as events
(outgoing, `sender.type` `agent_bot`), and a private note is the team's
(outgoing, `sender.type` `user`, `private` `true`), never the shopper's.
`conversation_status_changed` to `open` means the team has the conversation:
stop.

### 2.3 Fields read

Message (`app/models/message.rb:184-202`): `id`, `content`, `content_type`,
`content_attributes`, `message_type`, `private`, `created_at`, `source_id`,
`sender`, `inbox`, `account`, `conversation`, `attachments` when there are
any. `sender` is a person (`type` `user`), a bot (`type` `agent_bot`) or the
contact, which has no `type` but `contact_type` (`app/models/contact.rb`,
`webhook_data`; seen on the stand, §10).

Conversation in the payload
(`app/presenters/conversations/event_data_presenter.rb:2-50`): `id` (the
display id every call takes), `inbox_id`, `status`, `priority`, `labels`,
`custom_attributes`, `meta.sender` (the contact), `meta.assignee`,
`meta.assignee_type`, `meta.team`, and **only its last message**: read the
history through §5.1.

## 3. Files

The widget sends each file as a message of its own, **with no text**
(`app/javascript/widget/api/endPoints.js:46-62`); two photos are two messages
with one attachment each. The attachment is on the message before it is saved,
so `message_created` carries it. The upload limit is 40 MB by default
(`MAXIMUM_FILE_UPLOAD_SIZE`, `app/models/attachment.rb:208-212`).

An attachment (`app/models/attachment.rb:50-54`, `:124-135`): `id`,
`message_id`, `file_type` (`image`, `audio`, `video`, `file`, …), `extension`,
`content_type`, `file_size`, `width`, `height`, `data_url`, `thumb_url`.

What the AI service does with a file is its own rule. To count the shopper's
files in a conversation, use `shopper_files` of §5.1, not a sentence typed in
the chat.

## 4. Chatwoot calls with the bot's token

Send the token as `api_access_token: …` or `Authorization: Bearer …`
(`app/controllers/concerns/access_token_auth_helper.rb:18-27`). A bot token
reaches only these endpoints (lines 2-7); everything is under
`/api/v1/accounts/{account_id}/conversations/{conversation_id}`.

| Action | Call |
| --- | --- |
| Reply to the shopper | use §5.4; Chatwoot's `POST …/messages {"content": "…"}` (`message_type` defaults to `outgoing`) still works but is **not protected** against a take-over |
| Note for the team | `POST …/messages {"content": "…", "private": true}` |
| Typing indicator | `POST …/toggle_typing_status {"typing_status": "on" \| "off"}` |
| Hand over to the team | `POST …/toggle_status {"status": "open"}` (on Pending: Chatwoot's `bot_handoff!`, `conversations_controller.rb:83-100`) |
| Resolve | `POST …/toggle_status {"status": "resolved"}` |
| Priority | `POST …/toggle_priority {"priority": "low" \| "medium" \| "high" \| "urgent"}` |
| Give it to a team | `POST …/assignments {"team_id": 4}` |
| Conversation attributes | `POST …/custom_attributes {"custom_attributes": {…}}` |

Do **not** use Chatwoot's `POST …/labels`: it replaces every label of the
conversation, the team's included. Use §5.2.

**Act only on conversations of the connected inboxes, as delivered to you.**
Chatwoot lets a bot act on any conversation of its account
(`app/policies/conversation_policy.rb:11`, `:24-25`); our endpoints refuse
others, Chatwoot's do not, so the rule is yours to keep.

The API is throttled per IP, 3000 requests a minute by default
(`config/initializers/rack_attack.rb:128`).

## 5. Our calls with the bot's token

Under `/api/v1/accounts/{account_id}/inclamo/ai/conversations/{conversation_id}`,
the same token. Any other token, a person's session, or the token of a
disconnected account is `401`; a conversation outside the connected inboxes,
or one that does not exist, is `403` with nothing about it in the answer.

### 5.1 History and files

```
GET …/messages?limit=30        (at most 100)
```

```json
{
  "status": "pending",
  "inbox_id": 3,
  "priority": null,
  "labels": ["inclamo_intent_return"],
  "shopper_files": 2,
  "messages": [
    { "id": 901, "created_at": "2026-11-07T14:00:06Z", "role": "shopper", "text": "The box came broken", "files": [] },
    { "id": 902, "created_at": "2026-11-07T14:00:20Z", "role": "shopper", "text": "",
      "files": [{ "id": 55, "file_type": "image", "content_type": "image/jpeg", "file_size": 284113, "url": "https://…" }] },
    { "id": 903, "created_at": "2026-11-07T14:00:25Z", "role": "agent", "text": "Thank you, I see the photo.", "files": [] }
  ]
}
```

The last public messages, oldest first. `role` is `shopper` (incoming),
`agent` (our bot) or `team` (a person, or the helpdesk's own automation).
Private notes, activity messages and Chatwoot's template messages are left
out. `limit` is 30 by default, 100 at most. `url` is the file's address as in
the event's `data_url` (`app/models/attachment.rb`). `shopper_files` counts the files in all the shopper's public
messages of the conversation.

### 5.2 Labels

```
POST …/labels {"add": ["inclamo_intent_return", "inclamo_request_ready"]}
```

Adds the names and keeps every other label; answers the full list,
`{"labels": [...]}`. Only names starting `inclamo_` in Chatwoot's label form
(lower case letters, digits, `_`, `-`; `app/models/label.rb:25-34`), at most
100 characters each and 20 a request, are accepted; otherwise the answer is
`422` with `error` `invalid_label`, `too_many_labels` or `no_labels`, and none
of the request is added. A name the
account does not list yet is added to its labels with the description "Set by
the AI agent", so the team sees it.

### 5.3 A finished call

```
POST /api/v1/accounts/{account_id}/inclamo/calls
```

After a call of the AI phone agent ends, the AI service files it with one
request and the bot's token. The helpdesk puts it in the Phone inbox as a
conversation on the caller's contact, the turns as messages and the record as
a private note. The request, the answer, the contact rule and the refusals are
in [ai-connector-calls.md](ai-connector-calls.md). Telephony and recordings
stay in the AI service: the Phone inbox provides no voice service by itself.

### 5.4 Protected reply

```
POST …/reply {"content": "We have your order."}
```

Posts the text as the agent's public reply **only while the conversation is
Pending**. The helpdesk locks the conversation, reads its status and saves the
reply in one step; a person's take-over (a public reply, an assignment, the
dashboard's "Take over") changes the status inside its own step on the same
conversation. So the reply is either posted before the take-over or refused,
and never appears after it.

| Answer | Meaning |
| --- | --- |
| `201 {"id": 904, "created_at": "…"}` | posted; the message is the same as one made through Chatwoot's `POST …/messages` and gives the same events |
| `409 {"error": "conversation_not_pending", "status": "open", "message": "…"}` | the conversation is no longer the agent's (taken, handed over, resolved or snoozed); **nothing was posted** |
| `422 {"error": "empty_reply", "message": "…"}` | `content` is missing or blank |
| `422 {"error": "invalid_request"}` | Chatwoot refused the message itself, for example its limit of messages a minute in one conversation; nothing was posted |
| `401` / `403` | as for every call of §5 |

On `409 conversation_not_pending` **the turn did not happen**: do not send the
reply again, do not hand the conversation over, and make no further call for
that turn. The team has the conversation; the next shopper message in a
Pending conversation starts a new turn.

Send every reply to the shopper through this call. Chatwoot's
`POST …/messages` stays available and unchanged, but nothing in it looks at
who has the conversation: a reply composed before a take-over and sent through
it is posted after the take-over. Private notes, typing, labels, priority,
team assignment and resolving are not covered by this call.

## 6. Labels

Created at connection; an existing label of the same title is left alone.

| Label | Meaning |
| --- | --- |
| `inclamo_handover` | the team has the conversation from the agent |
| `inclamo_resolved` | the agent closed it |
| `inclamo_escalation` | a request was filed for the team |
| `inclamo_error` | the agent failed and handed over |
| `inclamo_limit` | the turn limit was reached, handed over |
| `inclamo_offline` | the shopper wrote through an offline form |
| `inclamo_urgent` | urgent (safety); priority `urgent` with it |
| `inclamo_request_ready` / `inclamo_request_incomplete` | a filed request with all / not all required data |
| `inclamo_intent_<id>` | the request's type; created when first added |

## 7. Who has the conversation

| What happens | The helpdesk does | The agent |
| --- | --- | --- |
| a new conversation in a connected inbox | starts it **Pending**, the bot as its AI assignee (`app/models/conversation.rb:316-333`) | answers |
| the agent hands over (`toggle_status open`) | Open, the AI assignee cleared, auto-assignment may give it to a person | stops |
| a person replies publicly or takes it (assigns; the dashboard's "Take over") | opens it in the same step as the person's action: Chatwoot's assignment service for an assignment while the bot is the AI assignee (`app/services/conversations/assignment_service.rb:16-27`), **our overlay** for a public reply (Chatwoot CE does not, `message.rb:423-433`) and for any other assignment | gets `conversation_status_changed`, stops; a protected reply (§5.4) is refused from that moment |
| a delivery fails (§2.1) | Open, the bot still its assignee (§10.3) | — |
| the agent fails after answering `200` | nothing by itself | sends one message to the shopper through §5.4 **first**, then **hands over with `inclamo_error`** (after the hand-over the protected reply is refused) |
| the shopper writes in a resolved conversation | Pending again (`message.rb:435-444`) | answers |
| the AI agent is disconnected | every Pending conversation Open | gets no more events |

The team finds the agent's conversations under **Pending** in the conversation
list; Chatwoot's default list shows Open.

## 8. Testing against this contract

The helpdesk's end-to-end tests (`e2e/tests/ai-agent-connection.spec.mjs`,
`e2e/tests/ai-reply-ownership.spec.mjs`) run a stand-in agent,
`e2e/stand-in-agent/server.mjs`, that implements this contract by fixed rules
on the shopper's text: "person" or "human" hands over with a note and
`inclamo_handover`; "urgent" sets priority `urgent`, adds `inclamo_urgent` and
hands over; "resolve" replies and resolves; "intent" adds
`inclamo_intent_test`; "slow" holds its reply until the test releases it (or
for a set time), as a model that is still thinking; a message with files gets
a reply naming the files it received and `shopper_files`; anything else gets
a reply. Every reply goes through the protected reply (§5.4), and a
`409 conversation_not_pending` ends the turn without another call. The
`ai-reply-ownership` tests that need the stand-in's log or its token are
skipped against the AI service. Its own tests
(`node --test e2e/stand-in-agent/server.test.mjs`) show that it refuses a wrong
signature, a timestamp older than five minutes and a repeated delivery.

The tests assert what the helpdesk shows and stores, never the agent's words.
The same file runs against the AI service:

1. Run the tests against a helpdesk the AI service can reach (public, HTTPS):
   `HELPDESK_URL`, `E2E_ACCOUNT_ID` and the test users (`STAND_ADMIN_EMAIL`,
   `STAND_ADMIN_PASSWORD`, `STAND_AGENT_EMAIL`, `STAND_AGENT_PASSWORD`), in an
   account that was never connected.
2. Have the AI service issue a connection code for that helpdesk and set it as
   `E2E_AI_CODE`. Optionally set `E2E_AI_REFUSED_CODE` to a code the AI service
   refuses (expired, for example).
3. `npx playwright test tests/ai-agent-connection.spec.mjs` in `e2e/`.

With `E2E_AI_CODE` set, the tests connect with that code and skip what only
the stand-in can show: what it received and with which signature, answering
`503` on purpose, and reading or replying with the bot's token. The
"The AI service refuses the code" test is skipped without
`E2E_AI_REFUSED_CODE`. The AI service has to act on the same kinds of text as
the stand-in (a request for a person, an urgent request, a closing thanks, a
photo) for the handover, urgency and resolution tests to pass.

## 9. Versions

The registration carries `"contract": 1`. A change that breaks a field or a
call of this document raises the number; the AI service refuses a contract it
does not know with a `4xx` and a message.

Additions that change no existing field or call keep the number. The
protected reply (§5.4) is one: an AI service written before it keeps working
through `POST …/messages`, without its protection.

## 10. Event examples

Examples for Chatwoot 4.19.1 with the overlay. Identifiers are synthetic;
signed file addresses, tokens and names are omitted.

### 10.1 A widget message with one image

A file the shopper sends from the widget is a message of its own, with
`content` `null`. The top-level `sender` of a shopper has no `type`; the
contact in `conversation.meta.sender` has `"type": "contact"`.

```json
{
  "event": "message_created",
  "id": 13,
  "message_type": "incoming",
  "private": false,
  "content": null,
  "content_type": "text",
  "content_attributes": { "in_reply_to": null },
  "created_at": "2026-11-07T17:30:22.743Z",
  "account": { "id": 1, "name": "E2E" },
  "inbox": { "id": 1, "name": "E2E Website" },
  "sender": { "id": 3, "name": "…", "email": null, "phone_number": null, "contact_type": "lead", "account": { "id": 1, "name": "E2E" } },
  "attachments": [
    { "id": 1, "message_id": 13, "file_type": "image", "extension": "png", "content_type": "image/png", "file_size": 162,
      "width": null, "height": null,
      "data_url": "http://rails:3000/rails/active_storage/blobs/redirect/…/box-front.png",
      "thumb_url": "http://rails:3000/rails/active_storage/representations/redirect/…/box-front.png" }
  ],
  "conversation": {
    "id": 3, "inbox_id": 1, "status": "pending", "priority": null, "labels": [], "channel": "Channel::WebWidget",
    "meta": { "sender": { "id": 3, "type": "contact", "…": "…" }, "assignee": { "id": 3, "name": "AI agent", "type": "agent_bot" }, "assignee_type": "AgentBot", "team": null },
    "messages": ["the last message only, as above"],
    "contact_inbox": { "source_id": "…", "pubsub_token": "…" }
  }
}
```

A new widget conversation also brings Chatwoot's own `template` messages ("Give
the team a way to reach you.", "Get notified by email"), each as
`message_created` and `message_updated`, with no sender: not the shopper's,
no turn.

### 10.2 After the agent hands over

`toggle_status open` on a pending conversation (`bot_handoff!`), in the order
the stand-in received them:

| Event | What changed |
| --- | --- |
| `conversation_opened` | `status` `open` |
| `conversation_status_changed` | `status` `open` |
| `conversation_updated` | `status` `pending` → `open`, `assignee_agent_bot_id` → `null`, `ai_assignee_type` → `null` |
| `message_updated` (each message) | `conversation.status` `open` |
| `conversation_updated` | `assignee_id` → a person: Chatwoot's auto-assignment |

The bot keeps getting the conversation's events after the handover: it is
still the inbox's bot.

### 10.3 A pending conversation after a `503`

The stand-in answered `503`; Chatwoot does not retry it and opens the
conversation (`lib/webhooks/trigger.rb:65-89`):

| Event | What changed |
| --- | --- |
| `conversation_opened` | `status` `open` |
| `conversation_status_changed` | `status` `open` |
| `conversation_updated` | `status` `pending` → `open` |

and an activity message in the conversation (Chatwoot's
`conversations.activity.agent_bot.error_moved_to_open`). Unlike a handover,
**the AI assignee stays**: the conversation is Open, assigned to the bot, and
Chatwoot's auto-assignment does not give it to a person.

## Governed Shopify actions (contract extension)

Staff rights are scoped per operation, independently from AI policy. Existing connection registration and bot-token authentication remain unchanged. A connected AI service can now use these endpoints under `/api/v1/accounts/:account_id/inclamo/ai/conversations/:display_id`:

- `GET /orders`: unambiguously matched customer, recent orders and current policies. The bot is limited to its connected account/inboxes. The helpdesk ignores widget-supplied remembered-customer attributes when matching AI targets.
- `POST /proposals`: `{ request_id, action_name, order_id | customer_id, params, address?, note? }`. Use a unique 8–64 character alphanumeric/hyphen request id and reuse it for delivery retries. Reusing it with different input is refused. Order-less operations omit target ids. Addresses are allowed only for `address`; notes only for note/new-order operations. Parameters follow the existing staff action contract. For item edits omit `expected`: the server calculates it.
- `GET /proposals/:id`: current proposal and underlying action outcome.
- `POST /proposals/:id/execute`: request autonomous execution. This never substitutes for staff approval when any required policy is `propose`.

All operations default to `propose`. Staff review, refresh, approve or reject proposals in the conversation. The exact request and server-calculated summary are bound to a review digest; proposals expire after 15 minutes. Addresses and notes in proposal storage are encrypted. A changed customer, order or connection requires refreshed review. A bot cannot supply a staff identity or grant itself permissions.

Autonomy requires explicit per-operation policy, current connected service/bot/inbox, a pending conversation without a human assignee and verified customer identity. A signed widget identifier must equal the matched Shopify customer GID or that customer's email read from Shopify; a signed contact email cannot authenticate another customer found by phone. Alternatively an administrator can explicitly verify the customer's identity from a proposal. That verification is bound to the channel, matched customer and contact identifiers; changes invalidate it. Merely approving one proposal does not establish ongoing identity trust.

For order operations, allowed fulfillment states and the maximum current order total are required. Refund amounts, calculated edited totals and calculated new-order totals must also fit their applicable limit. Amounts use the connected shop currency. Discount policies set maximum fixed amount and maximum percentage. These limits apply per operation, not cumulatively across a day. Cancellation with a refund requires both cancellation and refund authority; a discounted new order requires both new-order and discount authority. A policy set to `forbidden` also prevents human approval of an AI proposal; staff can still perform independently authorized manual actions.

`accepted` means Shopify accepted the operation; `pending`, `running` and `unknown` must never be described to the customer as completed. An unknown result keeps its original action identifier. The AI endpoint does not reissue its write; common read-only reconciliation can resolve it. An accepted action's private audit note names the AI initiator and the approving person, or labels autonomous execution. Returning an invoice link/code does not itself deliver a customer reply; the AI service must send the appropriate public reply only after checking the result.

Errors such as `approval_required`, `identity_unverified`, `human_takeover`, `amount_limit`, `state_limit`, `policy_forbidden`, `review_changed` and `expired` require a human review or changed verified conditions. `busy` means another proposal request holds the account execution lock; retry the same request id. Service failure/disconnection disables autonomy. Subscription enforcement remains the existing registration/delivery contract: the service must refuse delivery or disconnect when access is lost; the helpdesk cannot independently infer external billing status.

The acceptance simulator exercises these endpoints using the registered bot token inside the isolated test stack. Those results verify this integration contract and Shopify state, not real-model intent recognition or model quality.
