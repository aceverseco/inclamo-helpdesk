# AI connector: filing a finished call

> **Proposed** in change `call-conversations`; not in force until that change is
> approved. Part of the AI connector contract (`docs/ai-connector.md`, change
> `ai-agent-connection`).

After a call of the AI phone agent ends, the AI service files it in the
helpdesk with **one request**. The helpdesk puts it in the account's **Phone**
inbox as a conversation on the caller's contact, the caller's turns as
incoming messages and the agent's as outgoing ones, the record as a private
note, and shows a call card in the conversation sidebar.

## Request

```
POST /api/v1/accounts/{account_id}/inclamo/calls
api_access_token: <the access token of the connection's agent bot>
Content-Type: application/json
```

Only the agent bot of the account's AI agent connection may file a call. Any
other token, a user's included, is refused.

```json
{
  "call_id": "c-17",
  "entry": "inbound",
  "line": "+15550100100",
  "caller": { "phone": "+15550100001", "email": "anna@example.com", "name": "Anna" },
  "ended_at": "2026-11-07T14:03:12Z",
  "duration": 192,
  "outcome": "request",
  "needs_team": true,
  "priority": "urgent",
  "labels": ["inclamo_call", "inclamo_inbound", "inclamo_handover", "inclamo_escalation"],
  "recording_url": "https://example.com/calls/c-17",
  "turns": [
    { "role": "agent", "text": "Hello, you have reached the shop's assistant.", "at": "2026-11-07T14:00:01Z" },
    { "role": "caller", "text": "Hi, a part is missing from my order.", "at": "2026-11-07T14:00:06Z" }
  ],
  "record": "Request for the team · Inbound call · +1 555 010 0001 · 3 min 12 s · Inclamo AI agent\n\nSummary: …"
}
```

| Field | Rule |
| --- | --- |
| `call_id` | required; up to 100 characters of letters, digits, `_ : . -`; the call's key in the account |
| `entry` | `inbound` (to the shop's line), `outbound` (the agent called), `web` (storefront call button) |
| `line` | the shop's line in E.164, or absent (a web call has none) |
| `caller.phone` | E.164, or absent when the call came without a number |
| `caller.email` | the email of the store's customer with that number, when the AI service knows it; used only to find the contact |
| `caller.name` | optional, up to 255 characters |
| `ended_at` | ISO 8601 |
| `duration` | whole seconds, optional |
| `outcome` | a word of the AI service (`resolved`, `callback`, `parts_request`, `request`, `transfer_not_answered`, `failed`, `transferred`, `no_conversation`); a word the helpdesk does not know is shown as it is |
| `needs_team` | `true`: the conversation is open; `false`: resolved |
| `priority` | `low`, `medium`, `high`, `urgent`, or absent; send `urgent` for an urgent request |
| `labels` | at most 20, each `inclamo_` plus lowercase letters, digits or `_`; a label the account does not list yet is added to its list |
| `recording_url` | https only, optional; the helpdesk keeps the link and never fetches it |
| `turns` | at most 500, in the call's order; `role` is `caller` or `agent`; `text` up to 10,000 characters; `at` optional (missing times keep the order and end at `ended_at`) |
| `record` | up to 8,000 characters; written as a private note after the turns |

## Which contact the call goes to

First match wins:

1. the one contact whose phone number is `caller.phone`;
2. the one contact whose email is `caller.email`;
3. otherwise a new contact with the number, the email and the name, or
   "Unknown caller" ("Website visitor" for a `web` call).

Two or more contacts at step 1 or 2: none is chosen; a new contact gets the call
and the label `inclamo_match_ambiguous`. No number and no email: a new nameless
contact and the label `inclamo_no_caller_id`. A contact that existed is never
changed by a call.

## Answer

New call, `201`; a call filed before, `200` (nothing is changed, even when the
content differs: the first filing wins):

```json
{ "conversation_id": 412, "contact_id": 9031, "found": false, "matched_by": "phone", "labels_added": [] }
```

`matched_by` is `phone`, `email`, `created`, `anonymous` or `ambiguous`.

Refusals never echo the call's content:

| Status | `code` | Meaning | What the AI service does |
| --- | --- | --- | --- |
| 401 | — | not the connection's agent bot | stop; the connection needs attention |
| 409 | `not_connected` | the AI agent is not connected in this account, or switched off | retry on its schedule |
| 422 | `invalid_call` | a field breaks its rule | do not retry the same body |
| 422 | `invalid_label` | a label without the `inclamo_` prefix or of another form | do not retry the same body |
| 422 | `too_large` | more than 500 turns, a turn over 10,000 characters, or the record over 8,000 | file again in the short form (no turns, short record) |

## What the helpdesk never does with a call

- Send a message, email or webhook to the caller. The Phone inbox has no
  webhook URL and no agent bot.
- Wake the agent bot: no agent bot event for the messages of a filed call.
- Notify a teammate per turn: the call gives the notifications of a new
  conversation and of its assignment, as a chat does.
- Store a payment card number: digit runs of 13 to 19 that pass the Luhn check
  are stored as `[card number removed]`.
- Change an existing contact.

The merchant's own webhooks and automation rules see the call's conversation
and its record note, not each turn.

## What the team sees

The conversation in the Phone inbox, on the caller's contact next to their
chats; the turns as a chat; the record as the last private note; labels,
status and priority as sent; and a call card in the sidebar with the entry,
the line, the caller's number, the duration, the end time, the outcome in
words, how the contact was found, and the recording link.
