# AI connector contract, version 1

How an AI service (chat and voice agent) works with this helpdesk. The helpdesk
is Chatwoot Community Edition with our overlay; the AI service is a separate
product. The helpdesk delivers events and offers a few calls; everything the
agent decides is the AI service's.

Version 1, 2026-11-07, change `ai-agent-connection` (calls: change
`call-conversations`, [ai-connector-calls.md](ai-connector-calls.md)). The
registration call (§1.2) is the one part still to be confirmed by the AI
service's builder. Source lines are Chatwoot v4.19.1, paths relative to its
tree; `custom/` is ours.

```
 Shopper (widget)        Helpdesk                                 AI service
 ────────────────        ────────                                 ──────────
 message ──────────▶  conversation Pending, agent bot attached
                          │  agent-bot webhook, signed (§2)
                          └──────────────────────────────────▶  answers 200 at once,
                                                                 then runs the turn
                      ◀── reply, note, priority, hand over (§4) ──
                      ◀── history and files, labels (§5)        ──
 call (phone) ─────────────────────────────────────────────────▶ voice agent
                      ◀── the finished call (ai-connector-calls.md)
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

### 1.2 Registration (to confirm with the AI service)

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

### 1.3 Disconnecting

The administrator presses **Disconnect**. The helpdesk moves every Pending
conversation of the connected inboxes to the team (Open), detaches the bot,
destroys its token and the bot, then calls, best effort:

```
DELETE {service_url}/connections/{connection_id}
Authorization: Bearer {the bot's former access token}
```

The Phone inbox, its conversations and the labels stay.

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
- `message_type` is `incoming` and `sender.type` is `contact`;
- `private` is `false`;
- `conversation.status` is `pending`;
- `conversation.inbox_id` is one of the connected inboxes.

Ignore everything else for turns: your own replies come back as events
(`sender.type` `agent_bot`), and a private note is the team's, never the
shopper's. `conversation_status_changed` to `open` means the team has the
conversation: stop.

### 2.3 Fields read

Message (`app/models/message.rb:184-202`): `id`, `content`, `content_type`,
`content_attributes`, `message_type`, `private`, `created_at`, `source_id`,
`sender` (`type`: `contact`, `user`, `agent_bot`), `inbox`, `account`,
`conversation`, `attachments` when there are any.

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
| Reply to the shopper | `POST …/messages {"content": "…"}` (`message_type` defaults to `outgoing`) |
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
the same token, refused (`403`) for a conversation outside the connected
inboxes.

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
`agent` (our bot) or `team` (a person). Private notes and activity messages
are left out. `shopper_files` counts the files in all the shopper's public
messages of the conversation.

### 5.2 Labels

```
POST …/labels {"add": ["inclamo_intent_return", "inclamo_request_ready"]}
```

Adds the names and keeps every other label; answers the full list. Only names
starting `inclamo_` in Chatwoot's label form (lower case letters, digits, `_`,
`-`; `app/models/label.rb:25-34`) are accepted, others are `422`. A name the
account does not list yet is added to its labels with the description "Set by
the AI agent", so the team sees it.

### 5.3 A finished call

One request per call: [ai-connector-calls.md](ai-connector-calls.md).

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
| `inclamo_call`, `inclamo_inbound`, `inclamo_outbound`, `inclamo_web`, `inclamo_callback`, `inclamo_parts_request`, `inclamo_transferred`, `inclamo_no_conversation`, `inclamo_match_ambiguous`, `inclamo_no_caller_id` | calls, see ai-connector-calls.md |

## 7. Who has the conversation

| What happens | The helpdesk does | The agent |
| --- | --- | --- |
| a new conversation in a connected inbox | starts it **Pending**, the bot as its AI assignee (`app/models/conversation.rb:316-333`) | answers |
| the agent hands over (`toggle_status open`) | Open, the AI assignee cleared, auto-assignment may give it to a person | stops |
| a person replies publicly or takes it (assigns) | **our overlay** opens it (Chatwoot CE does not, `message.rb:423-433`) | gets `conversation_status_changed`, stops |
| a delivery fails (§2.1) | Open | — |
| the agent fails after answering `200` | nothing by itself | **hands over with `inclamo_error`** and one message to the shopper |
| the shopper writes in a resolved conversation | Pending again (`message.rb:435-444`) | answers |
| the AI agent is disconnected | every Pending conversation Open | gets no more events |

The team finds the agent's conversations under **Pending** in the conversation
list; Chatwoot's default list shows Open.

## 8. Testing against this contract

The helpdesk's end-to-end tests run a stand-in agent (`e2e/stand-in-agent/`)
that implements this contract by fixed rules, so every flow runs without the AI
service. The tests assert what the helpdesk shows, never the agent's words: the
same test file runs against the AI service given a connection code it issued
(the variables are named when that test file is written).

## 9. Versions

The registration carries `"contract": 1`. A change that breaks a field or a
call of this document raises the number; the AI service refuses a contract it
does not know with a `4xx` and a message.
