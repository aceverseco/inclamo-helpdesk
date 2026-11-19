# Turning on app provisioning

For the operator of an installation. A hosted helpdesk can give a Shopify
store its account when the operator's store app asks for one: the app sends a
signed request, the helpdesk creates the account and its first administrator,
suspends it when the app is removed from the store and restores it when the
app returns. What the app sends and what it is answered is the contract in
`docs/app-provisioning.md`; what the helpdesk promises is the behavior contract
[app-provisioned-account](behavior/app-provisioned-account/spec.md). This page
is the installation's side: the secret, its rotation, the limits, the record
and the task for accounts made by hand.

An installation that does not set the secret has none of this. Its
addresses under `/inclamo/provisioning/` answer `404` like any unknown address,
and nothing else on this page applies to it. A self-hosted installation needs
no setting to stay that way.

The same secret, limits and record serve the storefront chat: an account
created this way gets a website inbox for the store's chat, and the app asks
for the two public values its widget needs on two more addresses
(`.../stores/{shop_domain}/storefront-chat`; contract in
`docs/app-storefront-chat.md`, behavior contract
[app-storefront-chat](behavior/app-storefront-chat/spec.md)). It has no
setting of its own.

The same secret also signs the helpdesk's own requests to the app for a key to
a store, which connect such an account to its store without anyone entering
credentials (contract in `docs/app-store-access.md`, behavior contract
[app-store-access](behavior/app-store-access/spec.md)). That needs the app's
address; see [Store keys from the app](#store-keys-from-the-app).

The same channel carries Shopify's request to erase a store, which the app
passes on after the store uninstalled it (`.../stores/{shop_domain}/erasure`;
contract in `docs/app-store-erasure.md`, behavior contract
[app-store-erasure](behavior/app-store-erasure/spec.md)). Its settings, the
daily run and the journal are described under
[Erasing a store on Shopify's request](#erasing-a-store-on-shopifys-request).
It also carries Shopify's two requests about one shopper of a store, to erase
the shopper's data or to give the store owner a copy of it
(`.../stores/{shop_domain}/shoppers/erasure`, `.../shoppers/data-request`,
and `.../shoppers/requests` for how many wait), which become tickets for the
store's administrators: see
[Requests about one shopper](#requests-about-one-shopper).

## Settings

All are environment variables of the helpdesk's web process, and the secret,
the two store key settings, the shopper's waiting time and the erasure
journal's place of its worker process too (in the development stack,
`dev/.env`; see `dev/env.example`). They are read when the process starts:
restart it after changing one.

| Setting | Default | Meaning |
| --- | --- | --- |
| `INCLAMO_APP_PROVISIONING_SECRET` | unset | The secret shared with the store app. Setting it turns provisioning on |
| `INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS` | unset | The secret before a rotation, accepted next to the current one |
| `INCLAMO_APP_PROVISIONING_PUT_LIMIT` | `120` | `PUT` requests accepted in an hour, for the installation |
| `INCLAMO_APP_PROVISIONING_STORE_LIMIT` | `15` | `PUT` requests accepted in an hour for one store, every address's `PUT` counted together |
| `INCLAMO_APP_PROVISIONING_GET_LIMIT` | `300` | Status requests (`GET`) accepted in an hour, for the installation, every address's counted together |
| `INCLAMO_APP_PROVISIONING_ERASURE_LIMIT` | `60` | Erasure requests (a store's erasure and the two requests about one shopper, together) accepted in an hour, for the installation |
| `INCLAMO_APP_PROVISIONING_ERASURE_STORE_LIMIT` | `20` | The same requests accepted in an hour for one store |
| `INCLAMO_ERASURE_WAIT_DAYS` | `7` | Days between the app's first request to erase a store and the destruction of its account, a whole number from 0 to 21; any other value falls back to 7. Read by the web process (the date the app is answered) |
| `INCLAMO_SHOPPER_ERASURE_WAIT_DAYS` | `14` | Days between a ticket to erase one shopper and the automatic deletion of the shopper's data when no administrator deleted or held it, a whole number from 1 to 25; any other value falls back to 14. Read by the web process (the date the ticket and the app are given). See [Requests about one shopper](#requests-about-one-shopper) |
| `INCLAMO_ERASURE_JOURNAL_PATH` | unset | The file completed erasures are journaled to, outside the database. Read by the background workers and by the web process (an administrator's "Delete" in a ticket is journaled there). See [The journal](#the-journal) |
| `FRONTEND_URL` | Chatwoot's own | The address people open. The answers give it to the app as `helpdesk_url` and, for the storefront chat, as `widget_base_url`; the password link starts with it |
| `INCLAMO_APP_URL` | unset | The store app's address for store keys, HTTPS, with any path prefix the app chose (`https://app.example.com/helpdesk`). Used for a store whose provisioning request named no address of its own. Needed by the web and the worker processes |
| `INCLAMO_APP_KEY_PAUSE` | `30` | Seconds a store's connection waits before it asks the app for a key again while the app gives none. A longer `Retry-After` of the app is kept |

## The secret

1. Generate it: `openssl rand -hex 32`. It must be at least 32 bytes long. A
   shorter value is treated as not set, and provisioning stays off.
2. Set it as `INCLAMO_APP_PROVISIONING_SECRET` on the helpdesk and give the
   same value to the store app. Keep it where the installation's other secrets
   are kept. It is never written to a log or an answer; do not put it in a
   ticket or a chat either.
3. Make sure `FRONTEND_URL` is the public HTTPS address of the helpdesk.
4. Restart the web process. The addresses are drawn only when the process
   starts with the secret set.

To see that it is on without the app, send an unsigned request:

```sh
curl -s -o /dev/null -D - https://helpdesk.example.com/inclamo/provisioning/stores/example-store.myshopify.com | grep -i -E '^(HTTP|x-inclamo-provisioning)'
```

`401` with `x-inclamo-provisioning: 1` means provisioning is on and refused a
request that is not the app's; `404` without that header means it is off (the
secret is unset or too short, or the process was not restarted). Every answer
of an address under `/inclamo/provisioning/` carries the header while
provisioning is on, whatever its status, so the app tells "this store has no
account" from "this installation has no provisioning". A proxy in front of the
helpdesk must pass it through.

Whoever holds the secret can create accounts on the installation and name the
administrator of each new one. Treat a leak as a reason to rotate at once.

## Rotating the secret

The helpdesk accepts two secrets at a time so that the app can be switched
without a moment in which its requests are refused.

1. Generate a new secret. On the helpdesk, move the current value to
   `INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS` and set the new one as
   `INCLAMO_APP_PROVISIONING_SECRET`. Restart the web process.
2. Switch the store app to the new secret.
3. Remove `INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS` and restart again. From
   then on the old secret is refused.

After a leak, skip the overlap: set the new secret, leave the previous one
unset, restart, then switch the app. Its requests are refused in between and
it retries them.

The previous secret alone turns nothing on, and like the current one it is
ignored when shorter than 32 bytes.

## Store keys from the app

An account the store app provisioned is connected to its store through the
app: after the account is created or restored, a background job asks the app
for a short-lived key to the store (`POST {address}/stores/{shop_domain}/store-key`,
signed with the secret), checks it against the store and saves the connection.
The provisioning answer never waits for it. From then on the helpdesk asks for
a new key about five minutes before the current one ends, one request per
store however many people are working, and only when store data is needed.
The key is stored encrypted, deleted when the account is suspended, and never
logged or returned by an endpoint.

**The app's address.** The app may name an address for each store in its
provisioning request (`store_access_url`); the helpdesk keeps the latest one
and uses it for that store. A store without one uses `INCLAMO_APP_URL`. With
neither, or without the secret or Chatwoot's encryption keys, a provisioned
account simply has no store connection, the button "Connect through the
Inclamo app" is not shown, and no request leaves the helpdesk. The address
must be public HTTPS: requests go through Chatwoot's SSRF filter, which
refuses private addresses unless `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` is on (a
test stack only), and a redirect is not followed. Each request waits at most
10 seconds.

**From an unset address to a working panel.**

1. Set `INCLAMO_APP_URL` (next to the secret) on the web and the worker
   processes and restart both: a key is asked for by either.
2. In a provisioned account without a connection, an administrator opens a
   conversation; the Orders section offers **Connect through the Inclamo
   app**. Press it. Its answer says what went wrong if anything did (the app
   did not answer, answered for another store, lacks a scope, or does not
   have the store).
3. The Orders section shows the customer's orders, and its **Store** menu
   reads "Connected through the Inclamo app" with the last check and the last
   renewal of the key.

Accounts created or restored after step 1 are connected by themselves.

**When the app does not answer.** While the current key works (a key lives up
to an hour) nothing changes. After that the Orders section says the store's
data is temporarily unavailable and recovers by itself: the next request for
store data asks the app again, at most once per `INCLAMO_APP_KEY_PAUSE`
seconds per store. The connection is not marked broken. A conversation that
arrives meanwhile is handled as one whose store is silent: its automation rules
run without store facts. An outage of the app longer than a key's life stops
store data for every provisioned account at once, so watch the app as you
watch the helpdesk.

**When the app refuses.** `store_not_installed` marks the connection broken and
tells the account's administrator to install the app again; `account_mismatch`
marks it broken and tells them to contact support (the app does not know this
account for the store, for example because the store's account was made by
another installation). "Check again" asks for a new key and repairs the
connection once the app gives one. `503`, `422`, `429` and a server error count
as no answer.

**The alarm on 401.** The app answers `401` when it does not accept the
helpdesk's signature: the two sides do not hold the same secret (a rotation
done on one side only). Such a request is reported through Chatwoot's exception
tracker, which writes it to the error log as
`Inclamo::Shopify::AppKey::SecretRefused` and sends it to Sentry when
`SENTRY_DSN` is set. Alert on that name. The connections keep working on their
current keys meanwhile, then show the store's data as unavailable.

## Limits

The three limits count requests in fixed periods of one hour. A request over
a limit is answered `429` with `Retry-After` (seconds until the period ends),
creates nothing, and is recorded as `limited`. A value that is not a positive
whole number falls back to the default.

- Every `PUT` of the store app counts against the installation's limit and
  against the store's own, whichever address it goes to: the store's limit is
  one count for all of them.
- Every status call (`GET`) counts against the installation's status limit,
  whichever address it goes to.
- Only requests that carry a valid signature are counted, so traffic that is
  not the app's cannot use up the app's allowance. That traffic meets
  Chatwoot's own limit per address (`RACK_ATTACK_LIMIT`) like any other.
- A retry of a request that is answered from its stored answer, or told that
  the first is still being answered, is not counted: it is the same request.
  A request refused for its body (`422`) is counted.
- The removal notice is not limited.
- The erasure requests have counts of their own, for the installation and
  for one store, apart from the `PUT`s: a store's erasure and the two
  requests about one shopper count together. They follow the same rules: only
  signed requests count, a repetition from the stored answer does not, a
  request refused for its body does. The status call about a store's shopper
  requests (`.../shoppers/requests`) counts with the other status calls.
- The limits are Rack::Attack rules and follow Chatwoot's settings for it:
  with `ENABLE_RACK_ATTACK=false` there are no limits at all, and requests
  from an address on the allow-list (`127.0.0.1`, `::1` and those of
  `RACK_ATTACK_ALLOWED_IPS`) are never limited. If the store app reaches the
  helpdesk from such an address, for example over the loopback of the same
  machine, the limits do not apply to it.
- The counts are kept in Redis with Rack::Attack's other counts, and are
  shared by every web process of the installation.

The defaults are a first estimate for an installation with few installs a day.
Raise the installation's limit before a launch that brings many stores in one
hour. The limit for one store rarely needs changing: a store asks a few times
for its account and its storefront chat when it installs the app, and again
when it reinstalls it.

## Erasing a store on Shopify's request

Shopify asks the app, 48 hours after a store uninstalled it, to erase the
store's data. The app passes the request on, and the helpdesk:

1. schedules the erasure of the store's suspended account for the end of the
   waiting time (`INCLAMO_ERASURE_WAIT_DAYS`, 7 days by default), counted from
   the app's first request, and answers the app with that date. Nothing is
   destroyed yet. A store whose account is active (it installed the app again
   first) is refused, and nothing is scheduled;
2. withdraws the erasure when the store installs the app again before the
   date: its account is restored with everything it held;
3. once a day (the daily run at 04:10 in the workers' time zone) starts the
   erasure of every store whose date has passed and whose account is still
   suspended. An account the operator made active again by hand is not
   erased, and its erasure is withdrawn;
4. destroys the account with everything in it: conversations, messages and
   their files, contacts, inboxes, labels and settings, the store connection
   with its key, the AI agent's connection (the AI service is told), and every
   user who belonged to this account only. A user who also belongs to another
   account keeps it. The installation's super admins are never deleted;
5. counts the erasure as complete only when no table of the database names
   the account or its deleted users any longer. The store's row then keeps
   the store's domain, `erased` and the time; a later install gets a new,
   empty account.

Chatwoot leaves part of an account's deletion to the background workers, so
the destruction takes a little while after the daily run. While it lasts the
store is `erasing`. If a row still names the account after about a day of
attempts, the erasure stays `erasing` and the workers' log has a line that
begins with `[inclamo erasure] ALERT` and names the tables; the daily run
logs it again, and tries again, every day until it is resolved. A search of
the workers' log for that text is the operator's check.

Nothing undoes an erasure. Stored files go from the storage service with
their messages and contacts: on local storage (`ACTIVE_STORAGE_SERVICE=local`)
the files are deleted from the volume. On object storage the files are deleted
from the bucket; a versioned bucket keeps earlier versions until its own
lifecycle rules remove them.

### The journal

A backup of the database taken before an erasure does not hold its
completion, so restoring that backup brings the erased account back. Each
completed erasure is therefore also written, as one line of JSON, to a file
outside the database: `INCLAMO_ERASURE_JOURNAL_PATH`. A store's line names the
store's domain, the account's id and the times, and no person. A shopper's
line (see [Requests about one shopper](#requests-about-one-shopper)) names the
request, the store, the account, Shopify's order ids, the shopper's email and
phone as keyed digests only, whether an administrator or the helpdesk did it,
and the times.

- Set it on the background workers and on the web process to the same file,
  on a volume that is not part of the database and is not restored with it,
  and copy the file off the machine together with the backups. The process
  that completes an erasure creates the file (mode `600`) and appends to it.
- Without it, erasures still complete, and every completion logs a warning
  that it cannot be applied again after a restore.
- A path that cannot be written keeps a store's erasure `erasing`, with the
  alert above, until it can. An administrator's "Delete" in a ticket is then
  refused with a message and nothing is deleted; an automatic deletion is
  logged with `[inclamo erasure] ALERT` and tried again at the next daily run.

### After a restore

Right after the database is restored from a backup, before the store app
reaches the helpdesk again, run:

```sh
bundle exec rails 'inclamo:erasure:reapply[/path/to/the/journal]'
```

Without an argument it reads `INCLAMO_ERASURE_JOURNAL_PATH`. For every line
of the journal whose account the restored database holds again, it erases
that account again, as the daily run does, and prints one line for each:
`Store example-store.myshopify.com, account 42 (erased 2026-11-27T04:10:12Z): erased again`.
An account created after the erasure is never taken, whatever its id. It
waits up to ten minutes (`WAIT=<seconds>` to change it) for the background
workers to finish each one, so start them first; an erasure they have not
finished by then is reported as still being erased and is finished by them.

For a shopper's line it deletes again, in that account, every contact made
before the erasure was completed whose email or phone has the line's digests,
with what the helpdesk keeps about it and about the line's orders, and
finishes the line's ticket when the restore brought it back unfinished, as it
was finished (by the same administrator, or automatically, at the same time).
It prints
`Shopper of store example-store.myshopify.com, account 42, request 7 (erased 2026-12-04T04:10:12Z): 1 contact(s) erased again, its ticket finished again`.
A ticket the restore brought back waiting or held whose completion the
journal does not hold stays as it is: its own date and hold decide.

Running it twice is harmless: the second run prints `Nothing to erase again.`

Backups are not rewritten. An erased account stays in the backups taken
before its erasure until they expire, so the installation's backup retention
decides how long erased data outlives the erasure there.

### The record

`inclamo_erasure_requests` holds one row per store erasure: the store's
domain, the account's id at the time, the state (`scheduled`, `erasing`,
`erased`, or `cancelled` when the store installed the app again in time), when
it was received and when it was completed, and the ids of the users deleted
with the account. It also holds one row per ticket about a shopper (see
below). A completed row is removed 90 days after completion by the daily run;
a waiting or held row is kept for as long as it is not done.

## Requests about one shopper

Shopify asks the app to erase one shopper's data (`customers/redact`) and to
give the store owner a copy of one shopper's data (`customers/data_request`).
The app passes each on, naming the shopper by the email and the phone Shopify
gave. The helpdesk looks for that shopper in the store's account only:
contacts whose email is the same without regard to letter case, and contacts
whose phone has the same digits. Nothing else is searched, so a conversation
the same person started under another email or on a channel without an email
or a phone is not found; an administrator can delete such a contact by hand.

When it finds any, it makes a **ticket** for the account's administrators and
answers the app with its state; the request itself deletes nothing.

- The tickets live in an inbox of the account named "Data requests" (in the
  account's language), an API inbox the helpdesk makes with the account's
  first such request. It has no members, so only the account's
  administrators see it, and no bot. Every ticket belongs to one contact of the
  account, "Shopify data requests", never to the shopper. Deleting that inbox
  or that contact by hand deletes the tickets with it; the next request makes
  new ones.
- A ticket is open, has the priority "high" and the label
  `inclamo_erasure_request` or `inclamo_data_request`, starts no SLA timer and
  is listed by none of the ready team queues. Its first note says what was
  asked, how many contacts and conversations were found and, for an erasure,
  the date of automatic deletion. The shopper's email and phone and the
  contacts found are shown on the ticket's card ("Data request", in the
  conversation sidebar's Manage tab), only to administrators, and only until
  the ticket is done.
- On an erasure ticket an administrator chooses **Delete** (the contacts found
  at that moment are deleted whole, with their conversations, messages and
  files, and what the helpdesk keeps about them and about the orders Shopify
  named), or **Hold** with a reason, which stops the automatic deletion until
  an administrator chooses **Lift hold**. From the hold on, the store answers
  for the request. On a data-request ticket the team answers the shopper from
  the contacts the card links to and an administrator chooses **Mark
  answered**; the helpdesk never closes it by itself.
- If nobody deleted and no hold stands, the daily run deletes the shopper's
  data on the date: `INCLAMO_SHOPPER_ERASURE_WAIT_DAYS` days after the ticket
  (14 by default). A suspended account is treated the same. A lifted hold does
  not start the days again: the data is deleted on the original date, or at
  the next daily run when that date has passed. A store's own erasure takes
  everything with the account, held tickets included.
- When a ticket is done, the shopper's email and phone, and the hold's
  reason, are removed from its row, and the email and the phone's digits are
  replaced with "[removed]" in every message of the ticket, where a colleague
  may have written them; a name or an address typed into a note by hand is
  not found. A last note says it is done, when, and by which administrator or
  that the helpdesk did it, and the ticket is resolved.
- The daily run writes reminders into tickets as private notes: for a waiting
  erasure 7 days and 1 day before its date, for a held one every 30 days, for
  a waiting data request on days 7, 14, 21 and 27.
- A private note of Chatwoot notifies only the people it mentions, and the
  inbox has no members, so a ticket's first note and every reminder mention
  every administrator the account has at that moment, never an agent. Each
  administrator gets Chatwoot's notification of a mention in the dashboard,
  and finds the ticket among their mentions; a mail is sent only where the
  installation sends mail and the administrator chose mail for mentions in
  their notification settings. The notes of a hold, its lifting and the end
  of a ticket mention nobody.

The app also asks how many of a store's requests wait, are held, or are
overdue (unmet 30 days after they were received), without any shopper's data.

What is kept: a ticket's row in `inclamo_erasure_requests` holds the kind, the
store, the account, the ticket's conversation, Shopify's order ids, the date
of automatic deletion, a hold (author, time and reason), who did it and when,
the time of the last reminder, and the shopper's email and phone encrypted at
rest while the ticket is open and as keyed digests (HMAC-SHA256 under a key
derived from the installation's `SECRET_KEY_BASE`) afterwards. A request that
finds nobody makes no row; it is recorded among the app's attempts. Neither
the email nor the phone is written to the request log, and no answer to the
app holds them.

## An account made by hand

A store whose account was created by hand before the app existed is not found
by its domain: the store's first request would create a second, empty account.
Tie the two together before the store asks:

```sh
bundle exec rails 'inclamo:provisioning:link[example-store.myshopify.com,42]'
```

The first argument is the store's permanent `myshopify.com` domain, the second
the account's id (the super admin console shows it). On success the task
prints `example-store.myshopify.com is linked to account 42 (active)`, and the
store's next request is answered `existed` with that account. A suspended
account is linked as suspended, and the store's next request restores it.

The task refuses, changes nothing and exits with an error when the domain is
not a `myshopify.com` domain, the account does not exist, the domain is
already linked, or the account is already linked to a store. There is no task
to undo a link.

The task works whether or not the secret is set, so accounts can be linked
before provisioning is turned on.

## What is kept

- `inclamo_provisioned_accounts`: one row per store, with its account, which
  of the account's inboxes is the storefront chat (empty once the team deletes
  that inbox), whether the app is installed (`active`) or was removed
  (`suspended`), and the app's address for the store's key requests when the
  app's latest request that gave one named it (`store_access_url`; every later
  request that gives one replaces it).
  Suspension itself is Chatwoot's account status, as the super admin console
  shows it; nothing of a suspended account is deleted.
- `inclamo_provisioning_events`: one row per request and removal notice, with
  the time, the store's domain, the request id and the outcome (`created`,
  `existed`, `restored`, `suspended`, `none`, `refused`, `limited`, and for
  the storefront chat's request `chat_created`, `chat_existed`,
  `chat_refused`; for the erasure request `erasure_scheduled`, `erasing`,
  `erased`, `none` or `refused`; `erasure_cancelled` when a scheduled erasure
  is withdrawn, with the request id of the `PUT` that restored the account, or
  without one when the daily run finds the account made active by hand; and
  `erased`, without a request id, when an erasure is completed; for the
  requests about one shopper `shopper_ticket_made`, `shopper_ticket_found` (a
  repetition answered from the ticket there is), `shopper_none`,
  `data_request_made`, `data_request_found`, `data_request_none` or `refused`,
  and, without a request id, `shopper_deleted`, `shopper_held`,
  `shopper_hold_lifted` and `data_request_answered` when a ticket is acted
  on). The
  helpdesk's own requests for a store key are recorded here too, with the
  account: `key_granted`, `key_refused:<the app's code>`
  (`store_not_installed`, `account_mismatch`, `store_unavailable`,
  `unauthorized`, `rate_limited`, ...), `key_no_answer`, and
  `key_invalid:<why>` for a key that was not taken (`other_store`,
  `short_life`, `unreadable`). It never holds an email, a name, a signature, a
  password link, a website token or a key. Rows older than 90
  days are removed once a day by `Inclamo::ProvisioningEventsCleanupJob`, on
  the `scheduled_jobs` queue of the normal Sidekiq schedule.
- Request ids and their answers for ten minutes, in Redis. This is the only
  place a password link is held, and only for those ten minutes: a stored
  answer is never written to a log or to the record above.

The request log shows the addresses with the store's domain in the path.
The person's email and name and the password link are filtered out of it.

The password link in an answer is a Devise reset link. It works once and for
the installation's `reset_password_within` (6 hours in Chatwoot v4.19.1). The
helpdesk sends no letter when it creates an account this way.

## Turning it off

Unset `INCLAMO_APP_PROVISIONING_SECRET` and restart: the addresses are gone
and the app's requests are answered `404`. Accounts created through it stay as
ordinary accounts, and their rows stay for the day it is turned on again.

Without the secret, or without any address of the app, the store connections
made through the app can no longer be renewed: each keeps working until its key
ends, then shows the store's data as unavailable.

Erasures Shopify asked for and the helpdesk already scheduled are still
carried out on their dates by the daily run.
