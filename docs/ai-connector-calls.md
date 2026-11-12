# AI connector: filing a finished call

Part of the AI connector contract ([ai-connector.md](ai-connector.md), §5.3).

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
other token, a user's included, is refused. The token is also taken as
`Authorization: Bearer <token>`.

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
| `caller.email` | the email of the store's customer with that number, when the AI service knows it; used to find the contact, and kept on a new contact when no contact has it |
| `caller.name` | optional, up to 255 characters; used for a new contact only |
| `ended_at` | required; ISO 8601 with its zone (`Z` or an offset) |
| `duration` | whole seconds as a number, up to 1,000,000, optional |
| `outcome` | required; a word of the AI service, up to 50 lowercase letters, digits or `_` (`resolved`, `callback`, `parts_request`, `request`, `transfer_not_answered`, `failed`, `transferred`, `no_conversation`); a word the helpdesk does not know is shown as it is |
| `needs_team` | required, `true` or `false`; it does not set the conversation's status. **Every filed call is stored resolved**, also a call with a request for the team: the team finds those by their labels (`inclamo_handover`, `inclamo_escalation`, `inclamo_callback` and the like) and by `priority` |
| `priority` | `low`, `medium`, `high`, `urgent`, or absent; send `urgent` for an urgent request |
| `labels` | at most 20, each `inclamo_` plus lowercase letters, digits or `_`; a label the account does not list yet is added to its list |
| `recording_url` | https only, up to 1,500 characters, optional; the helpdesk keeps the link and never fetches it |
| `turns` | at most 500, in the call's order, or absent; `role` is `caller` or `agent`; `text` not empty, up to 10,000 characters; `at` optional, ISO 8601 with its zone; a time later than the filing is stored as the time of the filing. The messages carry the turns' times when every turn has one; otherwise they are put one second apart, the last at `ended_at`. The order of the request is always kept |
| `record` | required; up to 8,000 characters; written as a private note of the AI agent after the turns |

## Which contact the call goes to

First match wins:

1. the one contact whose phone number is `caller.phone`;
2. the one contact whose email is `caller.email`;
3. otherwise a new contact with the number, the email and the name, or
   "Unknown caller" ("Website visitor" for a `web` call).

Two or more contacts at step 1 or 2: none is chosen; a new contact gets the call
and the label `inclamo_match_ambiguous`. No number and no email: a new contact
without them and the label `inclamo_no_caller_id`. A contact that existed is
never changed by a call.

One contact of an account holds a number or an email. A new contact therefore
carries the caller's number and email only when no contact has them: the new
contact of an ambiguous match is made without the shared number, which the
call's card still shows. A new contact gets the identifier
`inclamo:customer:<call_id>`.

## Answer

New call, `201`; a call filed before, `200` (nothing is changed, even when the
content differs: the first filing wins):

```json
{ "conversation_id": 412, "contact_id": 9031, "found": false, "matched_by": "phone", "labels_added": [] }
```

`matched_by` is `phone`, `email`, `created`, `anonymous` or `ambiguous`.

Refusals carry the code as `code` and, like the other calls of the connector,
as `error`, with a `message` for a person. They never echo the call's content,
and the helpdesk's log never holds the turns, the record, the caller, the line or the recording link:

| Status | `code` | Meaning | What the AI service does |
| --- | --- | --- | --- |
| 401 | — | not the connection's agent bot: no token, a user's token, another bot's, or the token of a bot removed by a disconnection | stop; the connection needs attention |
| 409 | `not_connected` | the token is an agent bot's, but the AI agent is not connected in this account or its Phone inbox is gone | retry on its schedule |
| 422 | `invalid_call` | a field breaks its rule, or there are more than 20 labels | do not retry the same body |
| 422 | `invalid_label` | a label without the `inclamo_` prefix or of another form | do not retry the same body |
| 422 | `too_large` | more than 500 turns, a turn over 10,000 characters, or the record over 8,000 | file again in the short form (no turns, short record) |

Disconnecting the AI agent removes its bot and the bot's token at once
([ai-connector.md](ai-connector.md) §1.3), so a call filed after a disconnection
is answered `401`, not `409`: the next connection has a new bot and a new token.

## What the helpdesk never does with a call

- Send a message, email or webhook to the caller. The Phone inbox has no
  webhook URL and no agent bot.
- Wake the agent bot: no agent bot event for the messages of a filed call.
- Notify a teammate per turn, or assign the call: it is filed resolved, so
  Chatwoot's automatic assignment leaves it alone. A teammate who replies to
  the caller or reopens the conversation takes it from there.
- Store a payment card number: digit runs of 13 to 19, with nothing or up to
  three spaces, dashes, dots, commas or slashes between the digits, that pass
  the Luhn check are stored as
  `[card number removed]`, in a turn, the record and the caller's name.
- Change an existing contact.

The merchant's own webhooks and automation rules see the call's conversation
and its record note, not each turn.

## What the team sees

The conversation in the Phone inbox, on the caller's contact next to their
chats, resolved; the turns as a chat; the record as the last private note;
labels and priority as sent; and a "Call" section in the conversation sidebar
with the entry, the line, the caller's number, the duration, the end time, the
outcome in words, how the contact was found, and the recording link.

The same fields are the conversation's custom attributes `inclamo_call_entry`,
`inclamo_call_line`, `inclamo_call_caller`, `inclamo_call_duration` (seconds),
`inclamo_call_ended_at`, `inclamo_call_outcome`, `inclamo_call_matched_by` and
`inclamo_call_recording`. They are defined in the account when the AI agent is
connected (with the first call, for an account connected earlier), so
conversation filters and automation rules can use them.

## Testing against this contract

`e2e/tests/call-conversations.spec.mjs` files the invented calls of
`e2e/fixtures/calls/` with the stand-in agent's token and reads the dashboard.
