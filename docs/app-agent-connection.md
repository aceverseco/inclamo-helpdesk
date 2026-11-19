# App agent connection contract, version 1

How a store app connects the AI agent to a store's helpdesk account without
anybody typing a connection code. It continues `app-provisioning.md`: the
account exists (that document), and now the agent is linked to it. The agent
itself, its events and its calls are `ai-connector.md`, unchanged.

Version 1. This document is the contract the app's side is built against. It
is written before the helpdesk's side is implemented: until the revision note
in §9 says otherwise, nothing here is live.

```
 Store app                              Helpdesk                          AI service
 ─────────                              ────────                          ──────────
 mints a one-time pairing token
 for the store
   │ PUT stores/{shop}/agent, signed
   └──────────────────────────────────▶ creates the agent bot, the
                                         Phone inbox and the labels
                                           │ POST {service_url}/connections
                                           │ Bearer {token}   (ai-connector.md §1.2)
                                           └───────────────────────────▶ accepts, answers
                                                                          connection_id, webhook_url
                                         attaches the bot to the store's
                                         storefront chat inbox, if any
   ◀── connected, inbox ids ────────────
```

The app connects the agent; it does not choose where the agent answers. The
helpdesk starts the agent in the store's storefront chat
(`app-storefront-chat.md`) and from then on the account's people decide on
the helpdesk's **AI agent** page (§4).

The AI service's registration interface is exactly the one of
`ai-connector.md` §1.2 and §1.3. Nothing is added to it. The only new thing
for the AI service is where the pairing token comes from: the app hands it to
the helpdesk in a request instead of a person pasting a code.

## 1. Where it exists

On an installation with app provisioning (`app-provisioning.md` §1), and only
for a store whose account was created through it and is active. Other
installations answer `404`. The helpdesk's **Settings → AI agent** page keeps
connecting with a code everywhere, including here.

| Call | Purpose |
|---|---|
| `PUT /inclamo/provisioning/stores/{shop_domain}/agent` | The store's account is connected to the agent (§3) |
| `GET /inclamo/provisioning/stores/{shop_domain}/agent` | How the connection is doing (§5) |
| `DELETE /inclamo/provisioning/stores/{shop_domain}/agent` | Disconnect (§6) |

## 2. Who is asking

The same secret, the same three headers, the same signing text, the same
refusals and the same use of the request id as `app-provisioning.md` §2. The
method and the path are part of the signed text, so the three calls above
each have their own signature.

A retry of `PUT …/agent` that arrives while the first request with the same
request id is still registering is answered `409 {"error":"in_progress"}`
with `Retry-After`, as `app-provisioning.md` §2.4 says for every call.

The helpdesk answers `PUT …/agent` within 15 seconds: it waits at most
10 seconds for the AI service (§3.2) and needs the rest for its own work. The
app waits 15 seconds for this call, instead of the 10 of
`app-provisioning.md` §7, and retries only after that.

The limits are those of `app-provisioning.md` §6: `PUT …/agent` counts with
the store's other `PUT`s, `GET …/agent` with the installation's status calls,
and `DELETE …/agent` is not limited.

## 3. Connecting

### 3.1 The request

```
PUT /inclamo/provisioning/stores/example-store.myshopify.com/agent
Content-Type: application/json

{
  "contract": 1,
  "service_url": "https://agent.example.com/channels/helpdesk",
  "token": "…"
}
```

| Field | Required | Meaning |
|---|---|---|
| `contract` | yes | `1` |
| `service_url` | yes | The AI service's address, the one a connection code would carry. HTTPS. Must be one of the addresses the helpdesk's operator allowed (§3.3) |
| `token` | yes | A one-time pairing token for this store, the one a connection code would carry. The helpdesk uses it once, as the bearer of `POST {service_url}/connections`, and keeps it nowhere |

The app mints `token` for the store it is acting for, immediately before the
request, with the lifetime it gives to codes today. The AI service recognises
its merchant by the token, as it does for a pasted code.

The request names no inboxes. An `inbox_ids` field sent anyway is ignored.

### 3.2 What the helpdesk does

What `ai-connector.md` §1.2 describes, in the same order: the agent bot, the
**Phone** API inbox, the registration call with `contract`, `helpdesk_url`,
`account`, `bot` (`id`, `access_token`, `secret`), `phone_inbox_id` and
`inbox_ids` (the list the helpdesk chose, §3.4); on `201` the bot's webhook,
the labels and the bot attached to those inboxes; on a refusal or no answer within 10 s nothing is left in the
account.

The registration's `helpdesk_url` (`ai-connector.md` §1.2) has the same
origin as the `helpdesk_url` of the provisioning answer
(`app-provisioning.md` §3.2), so an AI service that minted its token for that
origin and `account_id` can compare them.

### 3.3 The allowed address

The registration call hands the bot's access token and secret to
`service_url`. The helpdesk therefore sends it only to an address its operator
listed for the installation. `service_url` must equal a listed address
(a trailing slash is ignored). Any other address is refused with
`service_url_not_allowed` before anything is created and before any request
leaves the helpdesk. The app and the operator agree the address once, when
the installation is set up.

The list may hold several addresses, for example one for each of the app's
records in Shopify that the installation serves. Adding an address never
touches a connection made with another one.

### 3.4 Where the agent answers

The helpdesk chooses, at the moment of connecting:

- **The store's storefront chat inbox**, the one `app-storefront-chat.md`
  reports for the store, when it exists and has no other bot. The agent
  answers first there from the start. No other inbox of the account gets the
  agent, whatever inboxes the team has made.
- **No inbox** otherwise (the store has no storefront chat inbox, the team
  deleted it, or it has another bot). The account is connected for calls
  only: the bot, the **Phone** inbox and the labels exist, finished calls can
  be filed (`ai-connector-calls.md`), and no conversation of any inbox is held
  for the agent. The registration call then carries `"inbox_ids": []`.

The answer's `inbox_ids` (§3.5) says which of the two happened. So the app
creates the account first (`app-provisioning.md`), which gives the store its
storefront chat inbox, and connects the agent after that.

No call of this contract changes the inboxes afterwards. Repeating the
request does not attach a storefront chat inbox that appeared after the
connection (§3.5, `existed`). Where the agent answers after the connection is
the account's own matter (§4); the one thing the helpdesk does by itself is
to give the agent a storefront chat inbox made again after the team deleted
the earlier one (`app-storefront-chat.md` §6).

### 3.5 The answers

`201` when the account was connected by this request, `200` when the same
connection already existed:

```
{
  "contract": 1,
  "state": "connected",
  "outcome": "connected",
  "inbox_ids": [3],
  "phone_inbox_id": 12,
  "connected_at": "2026-11-17T10:05:00Z"
}
```

| `outcome` | Status | What happened |
|---|---|---|
| `connected` | `201` | The account was not connected; it is now |
| `existed` | `200` | The account is already connected to the same `service_url`, also when that connection was made earlier on the **AI agent** page with a code. Nothing was registered again, **the token was not used**, and the inboxes were not changed |

`inbox_ids` is the list of inboxes the agent answers in at the moment of the
answer. It is there for the app to show ("the agent answers in your site's
chat"); the app cannot set it. An empty list is "calls only".

No answer ever carries the bot's token or secret. The AI service received
them in the registration call and nowhere else.

### 3.6 Errors

Nothing is connected or changed by a request that ends in one of these.

| Status | `error` | When |
|---|---|---|
| `404` | `no_account` | The store has no account |
| `409` | `account_suspended` | The store's account is suspended; restore it first (`app-provisioning.md` §3) |
| `409` | `agent_connected` | The account is connected with another `service_url`; disconnect first |
| `409` | `busy` | The account's connection is being changed right now by another request; `Retry-After` in seconds |
| `422` | `service_url_invalid` | Not an HTTPS address |
| `422` | `service_url_not_allowed` | §3.3 |
| `422` | `agent_refused` | The AI service answered the registration with a `4xx`. The body adds `service_error`, the AI service's `error` verbatim, and `message`, its message |
| `422` | `contract_unsupported` | `contract` is not a version this installation speaks |
| `502` | `agent_not_answered` | The AI service gave no usable answer within 10 s |
| `503` | `not_ready` | The installation cannot keep the bot's secret (no encryption keys); the operator has to fix it |

`401`, the `409` answers about the request id and `429` are those of
`app-provisioning.md` §2.3, §2.4 and §6.

`service_error` is passed on unchanged, so the app can tell its AI service's
refusals apart. The store app's AI service, for example, answers
`invalid_token`, `wrong_helpdesk`, `wrong_account`, `already_connected` and
`store_inactive`.

After `agent_refused` or `agent_not_answered` the pairing token must be taken
as spent: mint a new one for the next attempt.

## 4. What the account's people see

The **AI agent** page shows the connection like any other: the inboxes, the
state, the last reply, the last failed delivery. It says the connection was
made by the store app instead of naming a person. An administrator can press
**Disconnect** there; the AI service is then told by the usual call
(`ai-connector.md` §1.3) and the status call (§5) answers `disconnected`. The
app should read that as the merchant's decision and offer to connect again,
not reconnect by itself.

The inboxes are the page's to choose, not the app's. An administrator adds
and removes them on the page without disconnecting, and the helpdesk tells
the AI service the new list first (`ai-connector.md` §1.4); the connection
stays the same, and so does its `connected_via`. The status call (§5) then
answers the new `inbox_ids`. With an AI service that does not implement that
call, the page changes them the way it always has: an administrator
disconnects and connects again there with a connection code and the inboxes
they pick, and the status call then answers `connected_via: "page"`. Either
way the app leaves that connection as it is. Nothing in this contract changes
the inboxes.

## 5. How the connection is doing

```
GET /inclamo/provisioning/stores/example-store.myshopify.com/agent
```

`200`:

```
{
  "contract": 1,
  "state": "connected",
  "connected_via": "app",
  "inbox_ids": [3],
  "phone_inbox_id": 12,
  "connected_at": "2026-11-17T10:05:00Z",
  "last_reply_at": "2026-11-17T11:40:12Z",
  "last_delivered_at": "2026-11-17T11:40:10Z",
  "last_failed_at": null,
  "last_error": null
}
```

| `state` | Meaning |
|---|---|
| `never_connected` | The account never had a connection; the other fields are empty |
| `connected` | The last delivery of an event to the AI service succeeded, or none was made yet |
| `failing` | The last delivery failed; `last_failed_at` and `last_error` (an HTTP status or an error class, never a body) say when and how. It becomes `connected` again on the next delivery that succeeds |
| `disconnected` | There was a connection; it was removed by the app, by an administrator, or by the account's suspension |

`connected_via` is `app` or `page`. `inbox_ids` is what the agent answers in
now, which may differ from what a connection of the app started with (§4).
`404 no_account` for a store without an
account. A suspended account answers with its last state, which is
`disconnected` (§7).

`never_connected` is a normal state for a live account: a store may have its
account and its storefront chat without an agent, for example when the app
connects the agent only for stores with a plan that includes it.

## 6. Disconnecting

```
DELETE /inclamo/provisioning/stores/example-store.myshopify.com/agent
```

`200 {"contract": 1, "state": "disconnected", "ai_service_told": true}`.

What happens is `ai-connector.md` §1.3: every Pending conversation of the
connected inboxes goes to the team, the bot and its token are removed at once
(a call with the token answers `401` from that moment), the AI service gets
`DELETE {service_url}/connections/{connection_id}` with the bot's former
token, best effort. `ai_service_told` is `false` when that call did not get a
`2xx`; the disconnection has happened all the same. The Phone inbox, its
conversations and the labels stay.

An account that is not connected answers `200` with its state
(`disconnected` or `never_connected`) and `"ai_service_told": true`. Repeating
the call changes nothing.

This is the call that takes the agent away from a store whose account stays,
for example when the merchant moves the store's support to another helpdesk.
It is not limited (`app-provisioning.md` §6).

## 7. Suspension and restoration

The removal notice of `app-provisioning.md` §5 disconnects the agent as part
of suspending the account, with everything §6 lists, including the call to the
AI service. The app does not need to send the disconnection first.

Restoring the account (`PUT` of `app-provisioning.md` §3) does not connect
the agent. The account stays `disconnected` until the app sends §3 again with
a new pairing token. The storefront chat inbox comes back with the account,
so that connection starts the agent in it again (§3.4).

## 8. Testing against this contract

The helpdesk's end-to-end stack runs a stand-in app and a stand-in agent
together: the stand-in app takes a pairing token from the stand-in agent and
makes the three calls. A checklist for the app's side:

1. The pairing token is minted for the store of the request, immediately
   before it, and a new one after any failed attempt. The app waits
   15 seconds for `PUT …/agent` before it retries (§2).
2. `service_url` is the address agreed with the helpdesk's operator, not a
   value taken from a request or a form.
3. The connection is asked for after the account exists, and the request
   carries no inboxes; `inbox_ids` of the answer is shown, never sent.
4. `existed` is treated as success.
5. `agent_connected` leads to an explicit disconnection and a new connection,
   with the merchant told that pending conversations go to the team.
6. `disconnected` that the app did not cause is shown as "disconnected in
   the helpdesk", not silently repaired; a connection with
   `connected_via: "page"` is left alone.
7. After a reinstall the agent is connected again; the restoration alone does
   not do it.

## 9. Versions

`contract: 1` is this document, and moves together with `app-provisioning.md`.
A field added to an answer is not a new version.

Revision note: written 2026-11-17 and revised 2026-11-19 as a draft to
agree; the helpdesk's side is not implemented yet. The store app's AI service
accepts `"inbox_ids": []` in its registration (§3.4). Open with the AI
service's builder: the call that tells it a live connection's new inboxes
(`ai-connector.md` §1.4).
