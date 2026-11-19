# App admin entry contract, version 1

How a store app lets a Shopify staff member open their store's helpdesk
account without a helpdesk password. It extends the app provisioning contract
(`app-provisioning.md`): the same installation, the same shared secret, the
same signature. The app says who the person is; the helpdesk decides whether
they get in and answers with a one-time address.

Version 1. Written before the helpdesk's side is implemented: until the
revision note in §8 says otherwise, nothing here is live.

```
 Staff member (Shopify admin)   Store app                          Helpdesk
 ────────────────────────────   ─────────                          ────────
 presses "Open helpdesk" ─────▶ knows the store and the
                                signed-in staff member
                                │  POST stores/{shop}/entry, signed
                                └────────────────────────────────▶ is this a user of the
                                                                   store's account? (§3)
                                ◀── one-time address, 60 seconds ──
 browser opens the address ──────────────────────────────────────▶ signed in, the store's
 at top level                                                      account is shown
```

The other way in stays as it is: the helpdesk's login page with email and
password. A person may use either.

## 1. The call

```
POST /inclamo/provisioning/stores/{shop_domain}/entry
Content-Type: application/json

{
  "contract": 1,
  "staff": {
    "email": "alex@example.com",
    "email_verified": true
  }
}
```

It exists only where provisioning exists (`app-provisioning.md` §1); elsewhere
it answers `404`, without the `X-Inclamo-Provisioning` header that every
answer of this call carries.

The request is signed as in `app-provisioning.md` §2.2, with the request id,
`POST` and this path in the signed text. The email is the signed-in staff
member's, under the guarantee of `app-provisioning.md` §3.1: taken from
Shopify's own statement about that person, never from a form or a parameter,
and sent with `email_verified: true` only when Shopify says so.

Any user of the store's account comes in this way by their email. The
helpdesk does not tell staff members, store owners and collaborators apart;
whether a collaborator of the store may use this button is the app's rule, as
in `app-provisioning.md` §3.1.

### 1.1 The request id is single-use

This call differs from the other provisioning calls in one rule: an
`X-Inclamo-Request-Id` the helpdesk has seen in the last ten minutes is
refused with `409 {"error":"request_id_reused"}` (after the signature passed,
as in `app-provisioning.md` §2.3), even with the same body. The app makes a new id for every
press of the button. An answered request is never retried; if the answer was
lost, the app asks again with a new id and a fresh timestamp.

The reason: a stored answer would hand the same address to whoever replays the
request.

## 2. The answer

`200`:

```
{
  "contract": 1,
  "entry_url": "https://helpdesk.example.com/inclamo/entry/…",
  "expires_in": 60
}
```

`entry_url` is the helpdesk's own one-time address,
`https://<helpdesk>/inclamo/entry/<token>`, where the token is an opaque
value. It carries no email and nothing else about the person. The helpdesk
serves it with `Referrer-Policy: no-referrer` and does not write the token to
its access log. Opening it signs in the named user and nobody else, and
opens the store's account, also for a person who belongs to several accounts.
It works once and stops working `expires_in` seconds after it was made, used
or not.

Rules for the app:

- Send the browser to `entry_url` at once, at top level (a new tab or the top
  window). The helpdesk does not render inside the Shopify admin's frame.
- Treat it as a credential: do not store it, do not log it, do not put it in
  analytics or error reports. Whoever opens it first is signed in.
- Do not fetch it from the server side; only the person's browser opens it.
- Ask for a new one on every press. Never reuse an address.

After that the person has an ordinary helpdesk session. It does not depend on
the Shopify admin: leaving the admin or closing the app does not end it, and
signing out of the helpdesk does.

An address that no longer works signs nobody in and shows the helpdesk's login
page, where the password form is.

## 3. Refusals

| Status | `error` | `message` (the app may show it as it is) | Meaning |
|---|---|---|---|
| `403` | `not_a_user` | "This email is not a user of this helpdesk account. Ask the account's administrator to invite you." | No user has this email, or the user is not a member of this store's account. One answer for both |
| `403` | `two_factor` | "Two-factor authentication is on for this user. Sign in on the helpdesk's login page with your password and code." | This way in does not ask for the code, so it is closed to users who turned the code on |
| `403` | `account_suspended` | "This helpdesk account is suspended." | The app was removed from the store (`app-provisioning.md` §5) |
| `404` | `no_account` | — | The store has no account; create it first (`app-provisioning.md` §3) |
| `422` | `staff_email_missing` | developer text | `staff.email` is absent or does not read as an email |
| `422` | `staff_email_unverified` | developer text | `staff.email_verified` is absent or not `true` |
| `422` | `contract_unsupported` | developer text | `contract` is not a version this installation speaks |
| `401` | `unauthorized` | — | The signature or the timestamp; no detail is given |
| `409` | `request_id_reused` | — | The request id was seen in the last ten minutes (§1.1) |
| `429` | `rate_limited` | — | §4; `Retry-After` in seconds |

Nothing is created by this call in any case: no user, no membership, no
account. A staff member who is refused as `not_a_user` gets in after an
administrator of the account invites their email in the helpdesk.

A user who was invited and has not yet confirmed the invitation is let in and
is confirmed by it.

`403` messages are English. The app may show them or its own words for the
same `error`.

## 4. Limits

Defaults, which an operator may change: 20 entry requests an hour for one
person in one store, 300 an hour for one store. A request over a limit is
answered `429` with `Retry-After` and gives no address. Requests refused with
`401` do not count.

Opening the address is also subject to the helpdesk's own limit on sign-ins
per network address. Many people behind one address opening the helpdesk in
the same few minutes may be asked to wait; the helpdesk then shows its own
"too many attempts" message on the login page.

## 5. What the helpdesk keeps

One record per request: the time, the store's domain, the outcome and, when a
user was found, the user's identifier. Never the email, and never the address
or its secret part.

## 6. What the app must not assume

- That an email known to Shopify is known to the helpdesk. A staff member's
  Shopify email and their helpdesk email may differ; then they are
  `not_a_user` and use their password, or are invited by the Shopify email.
  Once that invitation is accepted, the user with the Shopify email comes in
  through this call, whatever other users the same person has.
- That `200` means the person ended up signed in. The address may be opened
  too late; the person then sees the login page.
- That the answer can be cached per person. It cannot (§1.1, §2).

## 7. Testing against this contract

The helpdesk's end-to-end stack carries a stand-in app that makes this call
with a test secret. A checklist for the app's side:

1. The signed text uses `POST` and the `/entry` path; the body is signed as
   sent.
2. A new request id per press; no retry of an answered request.
3. `entry_url` goes to the browser at top level at once and is kept nowhere,
   including logs and error reports.
4. Each `403` is shown to the person with its message or the app's own words;
   `not_a_user` is not shown as an error of the app.
5. `404 no_account` leads to creating the account, not to an error page.
6. `429` is shown as "try again in a moment", honouring `Retry-After`.

## 8. Versions

`contract: 1` is this document, and it requires version 1 of the provisioning
contract. A field added to an answer is not a new version. A change to the
request, to the single-use rule or to the meaning of an answer is.

Revision note: written 2026-11-17 and revised 2026-11-19 as the proposed
target; the helpdesk's side is not implemented yet.
