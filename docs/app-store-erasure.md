# App store erasure contract, version 1

How a store app passes Shopify's three compliance requests to a hosted
helpdesk: erase a store, erase one shopper, provide one shopper's data.
Shopify sends these requests to the app, which is the Shopify app the merchant
installed; the conversations and contacts are in the helpdesk.

The helpdesk is a tool of the merchant's team. The store owner decides in
Shopify; a request about one shopper becomes a ticket in the merchant's own
helpdesk account, and an administrator there deletes, holds or answers. The
helpdesk carries the deletion out by itself only when nobody acted in time, so
that Shopify's deadline is kept.

Version 1. This document is the contract the app's side is built against. It
is written before the helpdesk's side is implemented: until the revision note
in §11 says otherwise, nothing here is live.

```
 Shopify                      Store app                         Helpdesk
 ───────                      ─────────                         ────────
 shop/redact ───────────────▶ checks Shopify's signature
 (48 h after uninstall)       │  POST stores/{shop}/erasure
                              └───────────────────────────────▶ schedules the erasure (§3)
                              ◀── scheduled, erase_after ──────
                                                                ... 7 days ...
                                                                destroys the account (§3.4)

 customers/redact ──────────▶ POST stores/{shop}/shoppers/erasure ─▶ makes a ticket for the
                              ◀── waiting, delete_after ───────  account's administrators (§4)
                                                                an administrator deletes
                                                                or holds with a reason;
                                                                otherwise deleted after 14 days

 customers/data_request ────▶ POST stores/{shop}/shoppers/data-request ─▶ makes a ticket (§5);
                              ◀── waiting, counts ─────────────  the team answers the shopper

                              GET stores/{shop}/shoppers/requests ─▶ how many wait, are held,
                              ◀── numbers only ────────────────  are overdue (§6)
```

What this contract does not cover: receiving Shopify's webhooks and checking
their signature, erasing what the app and the AI service keep themselves, and
the merchant terms that say who answers for shoppers' data. Those are the
app's own duties. Suspending an account when the app is removed is
`app-provisioning.md` §5.

## 1. Where it exists

The four calls exist only on an installation whose operator set the shared
secret of `app-provisioning.md` §2.1. Every other installation answers them
`404` like any unknown address. Every answer of the helpdesk at these
addresses carries `X-Inclamo-Provisioning: 1` (`app-provisioning.md` §1), so a
`404` without it means the installation has no provisioning.

| Call | Shopify's request | Purpose |
|---|---|---|
| `POST /inclamo/provisioning/stores/{shop_domain}/erasure` | `shop/redact` | Erase the store's account (§3) |
| `POST /inclamo/provisioning/stores/{shop_domain}/shoppers/erasure` | `customers/redact` | A ticket to erase one shopper (§4) |
| `POST /inclamo/provisioning/stores/{shop_domain}/shoppers/data-request` | `customers/data_request` | A ticket to provide one shopper's data (§5) |
| `GET /inclamo/provisioning/stores/{shop_domain}/shoppers/requests` | — | How many requests wait (§6) |

`{shop_domain}` is the store's permanent `myshopify.com` domain, as in
`app-provisioning.md` §1. It is the `shop_domain` of Shopify's payload.

## 2. Who is asking

Exactly as `app-provisioning.md` §2: the three headers, the signature over

```
<timestamp>.<request id>.<METHOD>.<path>.<raw body>
```

with the same secret, the 300-second window, `401 {"error":"unauthorized"}`
for a signature or a time that fails, and the two `409` answers about the
request id (`request_id_reused`, `in_progress`).

Make one request id for each request passed on, and repeat it, with the same
body bytes, on the app's retries of it. A second delivery of the same webhook
by Shopify may get a new id: every call here is safe to repeat (§3.2, §4.3,
§5). Inside ten minutes a repeated id is answered from the stored answer
(`app-provisioning.md` §2.4), so to learn how far a request is, send it again
with a new id, or use §6.

The app passes a request on only after it has checked Shopify's own signature
on the webhook. The helpdesk cannot check it.

## 3. Erase the store

### 3.1 The request

```
POST /inclamo/provisioning/stores/example-store.myshopify.com/erasure
Content-Type: application/json

{"contract": 1}
```

### 3.2 The answers

All `200`:

| `state` | Body | Meaning |
|---|---|---|
| `scheduled` | `{"contract":1,"state":"scheduled","erase_after":"2026-11-26T10:00:00Z"}` | The store's account is suspended and will be destroyed within a day after that time |
| `erasing` | `{"contract":1,"state":"erasing"}` | The destruction is running |
| `erased` | `{"contract":1,"state":"erased","erased_at":"2026-11-26T10:20:00Z"}` | Done |
| `none` | `{"contract":1,"state":"none"}` | The store never had an account here |

The erasure is not immediate. The helpdesk waits a time set by its operator,
7 days by default and never more than 21, counted from the first accepted
request. Repeating the request does not move the date and is how the app asks
how far the erasure is.

`409 {"error":"account_active"}`: the store's account is active, which means
the store installed the app again before this request arrived. Nothing is
scheduled. The app drops Shopify's request; it does not retry it.

### 3.3 What cancels it, and what does not

- A `PUT` for the store (`app-provisioning.md` §3) before `erase_after`
  restores the account and withdraws the erasure. If the store is uninstalled
  again, Shopify sends a new `shop/redact` and the app passes it on again.
- After the date nothing cancels it and nothing brings the data back.

### 3.4 What is destroyed and what is kept

Destroyed: the account, its conversations, messages and attached files, its
contacts, inboxes, labels and settings, the store connection with its key, the
AI agent's connection (the AI service is told, as on a disconnect), and every
user who belonged to this account only. A user who also belongs to another
store's account keeps that account and their password.

Kept: the store's domain, the fact of the erasure and its time.

After `erased`:

- `GET` of `app-provisioning.md` §4 answers `404 {"error":"no_account"}`;
- a storefront that still carries the erased account's website token gets the
  widget refused, as for an unknown token;
- a new `PUT` for the store answers `201` with `outcome: "created"`, a new
  `account_id` and an empty account. The app must not reuse the old
  `account_id`, website token or any other value of the erased account.

## 4. Erase one shopper

### 4.1 The request

```
POST /inclamo/provisioning/stores/example-store.myshopify.com/shoppers/erasure
Content-Type: application/json

{
  "contract": 1,
  "shopper": {"email": "pat@example.com", "phone": "+15556251199"},
  "order_ids": ["299938", "280263"]
}
```

| Field | Required | Meaning |
|---|---|---|
| `contract` | yes | `1` |
| `shopper.email` | one of the two | `customer.email` of Shopify's payload |
| `shopper.phone` | one of the two | `customer.phone` of Shopify's payload, as Shopify sent it |
| `order_ids` | no | `orders_to_redact` of Shopify's payload, as strings |

`422 {"error":"shopper_missing"}` when neither email nor phone is given.

### 4.2 What the helpdesk does

It finds contacts of that store's account only, by email without regard to
letter case and by phone compared on digits. A conversation the same person
started under another email, or on a channel that carries no email or phone,
is not found.

When it finds any, it makes one ticket in the account's **Data requests**
inbox, which only the account's administrators see. The ticket says what
Shopify asked, how many contacts and conversations were found, and the date of
automatic deletion. **The request itself deletes nothing.**

In the ticket an administrator either:

- chooses **Delete**: the contacts found, with all their conversations,
  messages and attached files, are deleted whole within a day, together with
  what the helpdesk keeps about the listed orders. Nothing is blanked instead
  of deleted;
- or puts a **hold** with a reason, which must be given. A hold stops the
  automatic deletion until an administrator lifts it. From then on the
  merchant answers for the request.

If nobody deleted and no hold stands, the helpdesk deletes by itself on
`delete_after`: 14 days after the ticket was made by default (an operator may
set 1 to 25). It adds reminders to the ticket before that date. A suspended
account is treated the same, although nobody can open the ticket there. A
lifted hold does not start the days again.

When the deletion is done, the ticket no longer shows the shopper's email or
phone and keeps only that it was done, when, and whether by an administrator
or automatically.

If the store's own erasure (§3) comes due first, everything goes with the
account, held requests included.

### 4.3 The answers

All `200`:

| `state` | Body | Meaning |
|---|---|---|
| `waiting` | `{"contract":1,"state":"waiting","contacts":1,"conversations":2,"delete_after":"2026-12-02T10:00:00Z"}` | A ticket waits for the team; deleted automatically after that time |
| `held` | `{"contract":1,"state":"held","held_at":"2026-11-20T09:00:00Z"}` | An administrator stopped the automatic deletion |
| `done` | `{"contract":1,"state":"done","done_at":"2026-11-19T08:00:00Z","done_by":"team"}` | Deleted; `done_by` is `team` or `automatic` |
| `none` | `{"contract":1,"state":"none","contacts":0}` | Nothing is held about this shopper, or the store has no account; no ticket |

Repeating the request for the same shopper answers the state of the ticket
that exists and does not move the date. After `done`, a new request makes a
new ticket only if the account holds matching contacts again.

The answer never holds a hold's reason, an administrator's name or anything
about the shopper.

## 5. Provide one shopper's data

```
POST /inclamo/provisioning/stores/example-store.myshopify.com/shoppers/data-request
Content-Type: application/json
```

The body is the same as §4.1, with `orders_requested` of Shopify's payload in
`order_ids`, and is refused the same way with `422 {"error":"shopper_missing"}`.

When the account holds matching contacts, the helpdesk makes one ticket in the
**Data requests** inbox that says a shopper asked for their data and links to
each contact found, with the number of conversations. The merchant's team
answers the shopper from there and marks the ticket answered. The helpdesk
reminds in the ticket and never closes it by itself: only the merchant can
answer the shopper.

```
{"contract":1,"state":"waiting","contacts":1,"conversations":3,"account_state":"active"}
```

`state` is `waiting`, `done` (marked answered) or `none`
(`{"contract":1,"state":"none","contacts":0,"conversations":0}`: nothing held,
no ticket). While `account_state` is `suspended` the team cannot open the
ticket.

The answer never holds the shopper's name, email, phone, any message or any
address of a contact. Nothing is deleted by this call.

## 6. How many requests wait

```
GET /inclamo/provisioning/stores/example-store.myshopify.com/shoppers/requests
```

```
{
  "contract": 1,
  "erasures": {"waiting": 1, "held": 1, "overdue": 0},
  "data_requests": {"waiting": 1, "overdue": 1},
  "account_state": "active"
}
```

`overdue` counts requests not done 30 days after they were received; those
requests are also counted in `waiting` or `held`. No shopper is named.
`404 {"error":"no_account"}` for a store without an account.

This is how the app follows requests without keeping a shopper's email: it
does not need to repeat §4.1 or §5 to learn a state.

## 7. What the helpdesk keeps about a request

Every accepted request is recorded with its kind, the store's domain, when it
was received, its state and when it was completed. For a request about one
shopper the record holds the email and the phone readable only while the
ticket is open, encrypted at rest, and afterwards only as keyed digests. The
helpdesk never writes them to its request logs. A completed record is kept
90 days.

The helpdesk's backups are not rewritten. After its database is restored from
a backup, the helpdesk applies again every erasure completed after the backup
was taken.

## 8. Limits and errors

The helpdesk limits these requests. The defaults, each of which an operator
may change: the three `POST`s together, 60 an hour for the installation and
20 an hour for one store, counted apart from the `PUT`s of
`app-provisioning.md` §6; the `GET` of §6 counts with the installation's other
status calls, 300 an hour (`app-provisioning.md` §6). As there, requests that
fail the signature or the time do not count, an answer repeated from the
stored answer does not count, and a request answered `422` does. Over a limit:
`429` with `Retry-After`. Shopify gives 30 days for each request, so the app
queues and retries.

| Status | Body | Meaning |
|---|---|---|
| `200` | see §3.2, §4.3, §5, §6 | Accepted or answered |
| `401` | `{"error":"unauthorized"}` | The signature or the time (§2) |
| `404` | `{"error":"no_account"}` | §6 for a store without an account |
| `404` | anything, without `X-Inclamo-Provisioning` | The installation has no provisioning |
| `409` | `{"error":"account_active"}` | §3.2 |
| `409` | `{"error":"request_id_reused"}` or `{"error":"in_progress"}` | The request id (`app-provisioning.md` §2.4) |
| `422` | `{"error":"shopper_missing"}` | §4.1, §5 |
| `422` | `{"error":"contract_unsupported"}` | A version this installation does not speak |
| `429` | `{"error":"rate_limited"}` + `Retry-After` | Retry later |
| `5xx` or no answer in 10 s | — | Retry with the same request id and the same bytes |

## 9. What the app must do

1. Subscribe to Shopify's three compliance topics, check Shopify's signature,
   answer Shopify `2xx`, and only then pass the request on.
2. Pass `shop/redact` on even when the store has installed the app again; the
   helpdesk refuses with `account_active` and the app drops it.
3. Retry on `409 in_progress`, `429`, a `5xx` and no answer, until another
   answer of §8 arrives; a request that keeps failing is an alert for the
   app's operator well inside Shopify's 30 days.
4. Show the merchant the `erase_after` date wherever it shows that the
   helpdesk is suspended, and say that installing again before it keeps the
   data.
5. Not keep a shopper's email or phone after passing a request on. To show the
   merchant that requests wait, use the numbers of §6 with a link into the
   helpdesk.
6. Say in its merchant terms, before the merchant gets a helpdesk account,
   that requests about a shopper arrive as tickets in the helpdesk, that the
   merchant's team acts on them, that an erasure nobody acted on is carried
   out after 14 days, and that a hold is the merchant's decision.
7. Erase its own copies (conversation mirrors, call records, transcripts,
   logs) on its own; this contract covers only what the helpdesk holds.
8. After `erased` (§3), forget the store's `account_id`, website token and any
   other value of the erased account.

## 10. Testing against this contract

The helpdesk's end-to-end stack carries a stand-in app that signs the four
calls with a test secret. An app's side can be tested against a development
installation that has the test secret set and short waiting times; ask its
operator for the address and the secret.

## 11. Versions

`contract: 1` is this document. A field added to an answer is not a new
version; the app ignores fields it does not know. A change to a request, to
the signature or to the meaning of an answer is a new version.

Revision note: written 2026-11-17 and reworked 2026-11-18 as the agreed
target; the helpdesk's side is not implemented yet.
