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

## Settings

All are environment variables of the helpdesk's web process (in the
development stack, `dev/.env`; see `dev/env.example`). They are read when the
process starts: restart it after changing one.

| Setting | Default | Meaning |
| --- | --- | --- |
| `INCLAMO_APP_PROVISIONING_SECRET` | unset | The secret shared with the store app. Setting it turns provisioning on |
| `INCLAMO_APP_PROVISIONING_SECRET_PREVIOUS` | unset | The secret before a rotation, accepted next to the current one |
| `INCLAMO_APP_PROVISIONING_PUT_LIMIT` | `30` | "The store has an account" and "the store has its storefront inbox" requests accepted in an hour, counted together, for the installation |
| `INCLAMO_APP_PROVISIONING_STORE_LIMIT` | `5` | The same requests accepted in an hour for one store |
| `INCLAMO_APP_PROVISIONING_GET_LIMIT` | `300` | Status requests accepted in an hour, for the installation |
| `FRONTEND_URL` | Chatwoot's own | The address people open. The answers give it to the app as `helpdesk_url` and, for the storefront chat, as `widget_base_url`; the password link starts with it |

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
curl -s -o /dev/null -w '%{http_code}\n' https://helpdesk.example.com/inclamo/provisioning/stores/example-store.myshopify.com
```

`401` means provisioning is on and refused a request that is not the app's;
`404` means it is off (the secret is unset or too short, or the process was
not restarted).

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

## Limits

The three limits count requests in fixed periods of one hour. A request over
a limit is answered `429` with `Retry-After` (seconds until the period ends),
creates nothing, and is recorded as `limited`. A value that is not a positive
whole number falls back to the default.

- Only requests that carry a valid signature are counted, so traffic that is
  not the app's cannot use up the app's allowance. That traffic meets
  Chatwoot's own limit per address (`RACK_ATTACK_LIMIT`) like any other.
- The removal notice is not limited.
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
hour. The limit for one store rarely needs changing: a store asks once for
its account and once for its storefront chat. A
retry of the same request is answered from the stored answer and creates
nothing, but it is counted like any other signed request.

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
  that inbox), and whether the app is installed (`active`) or was removed
  (`suspended`).
  Suspension itself is Chatwoot's account status, as the super admin console
  shows it; nothing of a suspended account is deleted.
- `inclamo_provisioning_events`: one row per request and removal notice, with
  the time, the store's domain, the request id and the outcome (`created`,
  `existed`, `restored`, `suspended`, `none`, `refused`, `limited`, and for
  the storefront chat's request `chat_created`, `chat_existed`,
  `chat_refused`). It never holds an email, a name, a signature, a password
  link or a website token. Rows older than 90
  days are removed once a day by `Inclamo::ProvisioningEventsCleanupJob`, on
  the `scheduled_jobs` queue of the normal Sidekiq schedule.
- Request ids and their answers for ten minutes, in Redis. This is the only
  place a password link is held, and only for those ten minutes.

The request log shows the addresses with the store's domain in the path.
The person's email and name and the password link are filtered out of it.

The password link in an answer is a Devise reset link. It works once and for
the installation's `reset_password_within` (6 hours in Chatwoot v4.19.1). The
helpdesk sends no letter when it creates an account this way.

## Turning it off

Unset `INCLAMO_APP_PROVISIONING_SECRET` and restart: the addresses are gone
and the app's requests are answered `404`. Accounts created through it stay as
ordinary accounts, and their rows stay for the day it is turned on again.
