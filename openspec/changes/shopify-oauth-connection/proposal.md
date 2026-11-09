## Why

Today a merchant connects their store by creating an app of their own in Shopify's Dev Dashboard, choosing its distribution, installing it and pasting its client ID and secret into the helpdesk (`docs/connect-shopify.md`). That is a developer's task, and the hosted edition was always meant to offer the other door: OAuth from an app the operator owns (`docs/spec-plan.md` §3.2, "one connection abstraction, two entry paths"). ADR 0070 puts it into this release: the merchant presses one button, approves the access on Shopify's own screen, and the store is connected.

## What Changes

- **"Connect with Shopify"** in the store connection dialog, for administrators of an account the operator has given a Shopify app. It sends the administrator to Shopify's consent screen for the store and back; the store is then connected exactly as it is today with credentials: the same panel, the same scopes deciding the actions, the same limited mode, the same removal. The credentials form stays as the second way in, and is the only one on an installation without an operator app.
- **Installing from Shopify connects too.** When the store owner opens the custom install link the operator sent, Shopify brings them to the helpdesk's app address; the helpdesk recognises the store the operator assigned to the account and connects it after the same consent.
- **Every Shopify redirect is checked** before anything is kept: the signed parameters, the one-time state bound to the browser that started the flow, the store domain, the granted scopes.
- **Expiring tokens from the first day.** The helpdesk asks for an access token that lives one hour and a refresh token that lives ninety days, and renews both by itself, also for an account nobody opens for weeks. Shopify forces this on public apps only; keeping one way of doing it means the same code serves a public app later.
- **The app's removal is noticed.** Shopify tells the helpdesk when the app is uninstalled: the tokens are deleted, the panel says the app was removed from the store, and an administrator can connect again. Earlier order action records stay.
- **Permissions that grow are asked for.** When a release of the helpdesk needs a scope the store has not granted, the administrator sees "Update permissions", which goes through the consent screen again with the full list.
- **Operator configuration per account:** the operator's app client ID and secret and the store it is meant for, set by the operator on the server, never by the merchant and never shown back.
- One callback address and one webhook address under `/inclamo/shopify/`, shared with `shopify-sign-in` (ADR 0070), which signs people in through the same app.

Not in this change: signing in through Shopify (`shopify-sign-in`), a public listing on the Shopify App Store and its review, erasing data on Shopify's compliance requests, an embedded app inside the Shopify admin, more than one store per account (unchanged).

## Capabilities

### New Capabilities
- `shopify-oauth-connection`: how an account's store is connected, kept connected and found disconnected through an app the operator owns: the consent flow from the helpdesk and from Shopify, the checks on every redirect, expiring tokens and their renewal, the app's removal, growing permissions, and the operator's configuration.

### Modified Capabilities
- none. The `shopify-connection` capability of `shopify-order-panel` is not archived yet; the requirements here sit next to it and keep every rule it states about scopes, limited mode, secrets, one store per account, broken connections and removal.

## Assumptions for the founder

> Founder, 2026-11-07: both Shopify changes in this release («да»); the changes are built in turn without further stops; the assumptions stand as written until the founder says otherwise.

1. **Custom distribution per merchant for now.** The operator creates one app per merchant in the operator's Partner organization, chooses custom distribution for that merchant's store and sends the install link. No Shopify review is needed and protected customer data is available to such an app; a public app (one app for every merchant) needs Shopify's review and is a later step that this design keeps open.
2. **The operator sets the app on the server** with a console command (client ID, client secret, the store's domain, per account). A page in the super-admin console comes later.
3. **The credentials form stays** next to the button, for merchants who prefer their own app and for installations without an operator app.
4. **Installing from Shopify connects the account the operator assigned to that store**, without a helpdesk sign-in: the operator's assignment and Shopify's signature are what bind them. A store no account is assigned to gets a page that says so and nothing is connected.
5. **Shopify's compliance requests are received, verified and recorded, not acted on.** Shopify requires them only of apps listed on the App Store; erasing data on request comes with the public app.
6. **Uninstalling the app keeps the connection's row** in a "removed from the store" state, without tokens, so the panel can say what happened; removing the connection in the helpdesk still deletes it.
7. **Tokens are renewed in the background** once a day for every connection whose refresh token has less than a week left, so an account nobody opens does not fall out after ninety days.

## Impact

- Backend: one table for the operator's app per account, new columns on `inclamo_shopify_connections` (refresh token, its expiry), a fourth way of getting a token next to client credentials and the legacy token, three non-API routes (app address, callback, webhooks), a daily renewal job, a console command.
- Dashboard: the connect dialog gains "Connect with Shopify" and "Update permissions"; the panel gains the "removed from the store" state. No new seam: the dialog is ours (`ConnectDialog.vue`). The callback ends on a small page of our own.
- The operator's Shopify app: non-embedded, App URL and allowed redirection URL pointing at the helpdesk, webhooks `app/uninstalled` and `app/scopes_update` subscribed, the same scope list as `docs/connect-shopify.md`.
- Docs: `docs/connect-shopify.md` gains the button path; a new operator guide `docs/operator-shopify-app.md`.
- Tests: backend specs, component tests, end-to-end tests through a stand-in for Shopify's consent screen in the test proxy, and one recorded run through the real consent screen on a development store.
