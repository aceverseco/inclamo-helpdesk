# App store access contract, version 1

How a hosted helpdesk reaches the Shopify store of an account that a store app
provisioned (`app-provisioning.md`), without a Shopify app of its own. The
helpdesk asks the app for a short-lived key to the store and calls Shopify
itself. The app's own token and refresh token never leave the app.

Version 1. This document is the contract the app's side is built against. It
is written before the helpdesk's side is implemented: until the revision note
in §8 says otherwise, nothing here is live.

```
 Helpdesk                                  Store app                    Shopify
 ────────                                  ─────────                    ───────
 needs the store's data, has no key
 or the key is about to end
   │  POST stores/{shop}/store-key, signed (§2)
   └────────────────────────────────────▶ checks the account (§3.2)
                                           makes a delegate token ────▶ delegateAccessTokenCreate
   ◀── key, its end, granted scopes (§3.3)
 orders, customers, order actions ────────────────────────────────────▶ GraphQL Admin API
 ...
 five minutes before the key ends: asks again
```

This is the reverse direction of `app-provisioning.md`: there the app calls
the helpdesk, here the helpdesk calls the app.

## 1. Where it exists

The helpdesk makes this call only for an account the app provisioned, only
on an installation whose operator set the shared secret
(`app-provisioning.md` §2.1), and only when it has an address of the app for
the store:

1. the `store_access_url` the app sent with the store's provisioning `PUT`
   (`app-provisioning.md` §3.1), the latest one that carried it; or else
2. the app's address the operator configured for the installation.

So one installation can serve stores of several app records, each record at
its own address. The address is HTTPS and may carry a path prefix of the
app's choosing:

```
POST {app address}/stores/{shop_domain}/store-key
```

`{shop_domain}` is the store's permanent `myshopify.com` domain, lower-case,
the same value the app used when it provisioned the account. The helpdesk does
not follow a redirect and waits 10 seconds for an answer.

## 2. Who is asking

The signature is the one of `app-provisioning.md` §2.2, with the same secret,
made by the helpdesk and checked by the app: the three headers
`X-Inclamo-Timestamp`, `X-Inclamo-Request-Id` and `X-Inclamo-Signature`, and
the signed text `<timestamp>.<request id>.<METHOD>.<path>.<raw body>`.

What differs in this direction:

- `path` is the path as the helpdesk sent it, **including the prefix** of the
  app's address.
- The app applies the checks of `app-provisioning.md` §2.3 (signature, a
  timestamp within 300 seconds) and answers `401 {"error":"unauthorized"}`
  with no detail.
- `X-Inclamo-Request-Id` is new on every request. A key is not something to
  replay: the app does not answer a repeated request id from a stored answer;
  it may refuse it as `401`.

Worked example, with the secret `test-secret-not-for-production-0123456789abcdef`
and the app's address `https://app.example.com/helpdesk`:

```
POST /helpdesk/stores/example-store.myshopify.com/store-key
X-Inclamo-Timestamp: 1794000000
X-Inclamo-Request-Id: 4e7c2a90-6d1b-4f38-a5c2-9b1e8d3f6a07

{"contract":1,"account_id":42,"scopes":["read_customers","read_orders","read_products","write_orders","write_draft_orders","write_customers","write_order_edits","write_discounts","read_locations","read_merchant_managed_fulfillment_orders"]}
```

has the signed text

```
1794000000.4e7c2a90-6d1b-4f38-a5c2-9b1e8d3f6a07.POST./helpdesk/stores/example-store.myshopify.com/store-key.{"contract":1,"account_id":42,"scopes":["read_customers","read_orders","read_products","write_orders","write_draft_orders","write_customers","write_order_edits","write_discounts","read_locations","read_merchant_managed_fulfillment_orders"]}
```

and signs to

```
X-Inclamo-Signature: sha256=b72c74f4156702aae0f7fa409326c14f19840cea15544d3d757b27fcae70d0b3
```

## 3. The key

### 3.1 The request

| Field | Meaning |
|---|---|
| `contract` | `1` |
| `account_id` | The helpdesk account asking: the `account_id` the helpdesk answered when the app provisioned the store |
| `scopes` | The Shopify access scopes the helpdesk can use. It asks for no others |

The scopes the helpdesk can use in this revision, and what each is for
(`connect-shopify.md` has the same table for merchants):

| Scope | Used for | Without it |
|---|---|---|
| `read_customers` | finding the customer of a conversation | the store is not connected |
| `read_orders` | showing orders | the store is not connected |
| `write_orders` | cancel, refund, address change, order tags and note | those actions are unavailable |
| `write_draft_orders` | a free replacement; a new order with a payment link | unavailable |
| `read_products` | the same two, and the catalogue search | unavailable |
| `read_locations` | putting refunded items back in stock | a refund works; items stay out of stock |
| `read_merchant_managed_fulfillment_orders` | the same | the same |
| `write_customers` | a customer's tags and note | shown, not changeable |
| `write_order_edits` | changing an order's items | unavailable |
| `write_discounts` | a discount code for a reply | unavailable |

The app delegates the intersection of three lists: the scopes the request
names, the scopes the app holds at the store, and the ten of this table. A
scope outside it is left out, as an unheld scope is (§3.3). A new scope is a
new revision of this table, which both sides read.

### 3.2 What the app checks before it answers

1. The signature (§2).
2. The store has the app installed. Otherwise `store_not_installed`.
3. `account_id` is the account the helpdesk answered when the app provisioned
   this store, and the store was provisioned through the installation whose
   secret signed this request. Otherwise `account_mismatch`. This is the check
   that stops a request for one store's key in another account's name; the
   app must keep the account id it was given at provisioning, and which
   installation gave it.

### 3.3 The answer

`200`:

```
{
  "contract": 1,
  "shop_domain": "example-store.myshopify.com",
  "access_token": "shppa_…",
  "expires_at": "2026-11-17T11:00:00Z",
  "scopes": ["read_customers", "read_orders", "write_orders"]
}
```

| Field | Meaning |
|---|---|
| `shop_domain` | The store the key opens. The helpdesk refuses a key for another store |
| `access_token` | A key to the store's Admin API with exactly the scopes in `scopes` |
| `expires_at` | When the key stops working, UTC |
| `scopes` | What the key carries: the scopes that were asked for, that the app holds at this store **and** that are in the table of §3.1. The helpdesk takes this list as the truth; it does not read the app's installation at the store to learn it |

**What the app must do.**

- Hand out a **delegate access token** made for this request
  (`delegateAccessTokenCreate` on the Admin GraphQL API), never the app's own
  access token and never its refresh token. Shopify lets a delegate token carry
  only scopes the app was granted and makes it live no longer than its parent
  ([Delegate API access](https://shopify.dev/docs/apps/build/authentication-authorization/delegate-api-access)).
- Delegate only scopes that are in the request, held by the app at the store
  and in the table of §3.1. A scope the request names that fails either of
  the other two is left out, not refused: the helpdesk then shows the actions
  that need it as unavailable.
- Give every key **at least 10 minutes** of life. A delegate token inherits its
  parent's remaining life, and an expiring offline token lives one hour
  ([Access tokens](https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/offline-access-tokens)),
  so when the app's own token has less than 10 minutes left the app refreshes
  it first and delegates from the new one. Read the delegate token's real end
  from the mutation's `expiresIn` (Admin API 2026-04 or later) rather than
  computing it. When Shopify answers `expiresIn: null`, answer as `expires_at`
  the time the key was made plus the life the app asked for, capped by the
  end of the app's own token. The helpdesk refuses a key with less than
  2 minutes left.
- Not log the key, and answer with `Cache-Control: no-store`.

**What the helpdesk does with it.** It stores the key encrypted, uses it for
its own calls to the store, asks again about five minutes before `expires_at`
(one request per account, however many people are working), and deletes it
when the account is suspended. It never returns the key to a browser and never
writes it to a log. An account nobody is using asks for nothing: a key is
requested when store data is needed, so expect at most about one request an
hour per active account, plus one when an administrator presses "check again".

**What the helpdesk keeps of what it reads with a key.** It writes no copy of
the store's customer or order records into its database. What the store
answers is kept in the helpdesk's cache for at most 60 seconds, per account,
and an order action makes the earlier answers of that account unreachable at
once. What stays in the merchant's account, for as long as the conversation,
the contact or the account exists:

- on a conversation, as its attributes: the order it is about (Shopify's id,
  the number, payment and fulfilment status, the first tracking number and
  link, and the link to the order in the Shopify admin), and facts about the
  customer for automation rules (whether they are a customer, their number of
  orders, amount spent and tags; the latest order's payment and fulfilment
  status, total and tags). Never a name, an email, a phone or an address;
- on a contact: the Shopify customer id an agent chose for it, or an
  administrator verified for the AI agent;
- a record of each order action taken in the helpdesk: who, the order and the
  customer by id and number, the action's parameters without the address and
  the note, the outcome and what it did (amounts, the ids of a refund, a draft
  or a new order, item titles), and a private note in the conversation that
  says it;
- for each order action the AI agent proposes, encrypted at rest: the request
  and what the team was shown to review it (the customer's id and email, the
  order's number, total and status, the effect);
- the text of messages and notes, including order details a reply put into
  its text.

None of what it reads is written to the helpdesk's logs, and addresses and
notes are filtered out of its request logs. An erasure
(`app-store-erasure.md`) removes it with the account, or with the shopper's
contacts and what the helpdesk keeps about the listed orders.

### 3.4 Refusals

`{"error": "<code>", "message": "…"}`; `message` is English text for a
developer's log.

| Status | `error` | When | What the helpdesk does |
|---|---|---|---|
| `404` | `store_not_installed` | The store does not have the app (never had, or uninstalled) | Marks the store connection broken and tells the administrator to install the app again |
| `403` | `account_mismatch` | `account_id` is not the account provisioned for this store, or the store's account was provisioned through another installation | Marks the connection broken and tells the administrator to contact support |
| `503` | `store_unavailable` | The app cannot make a key now: it cannot refresh its own token, or the store is frozen. `Retry-After` in seconds is welcome | Keeps the connection, shows "the store's data is temporarily unavailable" once its current key has ended, tries again later |
| `401` | `unauthorized` | §2 | The same as no answer, and alerts the operator: the two sides disagree on the secret |
| `422` | any | The request did not read (`contract_unsupported`, a malformed scope list) | The same as no answer |
| `429` | `rate_limited` | With `Retry-After` | The same as no answer |
| `5xx`, nothing in 10 s | — | | The same as no answer |

"The same as no answer": while the helpdesk still holds a key that works, the
team notices nothing. After that key has ended the panel says the store's data
is temporarily unavailable, and the helpdesk asks again when store data is next
needed, no more often than every 30 seconds per account.

Use `store_not_installed` only when it is true. It is the one answer that
tells a merchant's team their app is gone.

## 4. When things change at the store

- **The app is uninstalled.** The app sends the removal notice of
  `app-provisioning.md` §5; the helpdesk suspends the account and deletes the
  key. A request for a key that still arrives is answered
  `store_not_installed`.
- **The app's scopes at the store change.** The app changes nothing for keys
  it has handed out. The next key it hands out lists the new scopes; the
  helpdesk reads them on its next request or when an administrator presses
  "check again". When the store answers a call with `ACCESS_DENIED`, the
  helpdesk asks for a new key.
- **The app refreshes its own token.** Delegate tokens made from the earlier
  one are not extended; the helpdesk keeps to `expires_at` and asks again in
  time.

## 5. Limits

The app may limit requests per store; the pattern in §3.3 is the normal load.
A request over the limit is answered `429` with `Retry-After`. A limit of 30
requests an hour for one store is enough for the helpdesk.

The helpdesk and the app spend the same request allowance at the store
(Shopify counts per app and store). The helpdesk's calls are those of its
order panel and order actions: a few per conversation opened.

## 6. Summary for the app's side

1. Verify the signature over
   `<timestamp>.<request id>.POST.<path with prefix>.<raw body>`; the worked
   example in §2 reproduces.
2. Keep the helpdesk `account_id` from provisioning, and the installation
   that gave it, and compare both (§3.2).
3. Refresh the app's own token when under 10 minutes remain, then delegate.
4. Delegate the intersection of the asked scopes, the held scopes and the
   table of §3.1; return that list in `scopes`.
5. Return the real `expires_at`, or the computed one when Shopify gives none
   (§3.3).
6. Never return the app's own token or refresh token; never log the key.
7. Answer `store_not_installed` only for a store without the app, and
   `store_unavailable` for everything temporary.

## 7. Testing against this contract

The helpdesk's end-to-end stack carries a stand-in app that hands out keys
with a chosen scope list and life, and can answer each refusal of §3.4 or stay
silent. An app's side can be tested against a development installation of the
helpdesk that has the test secret and the app's address set; ask its operator.

## 8. Versions

`contract: 1` is this document. A field added to the answer is not a new
version; the helpdesk ignores fields it does not know. A change to the
request, to the signature or to the meaning of an answer is a new version.

Revision note: written 2026-11-17 and revised 2026-11-19 as the proposed
target; the helpdesk's side is not implemented yet, and what a delegate token
may read at a store is still to be confirmed on a development store.
