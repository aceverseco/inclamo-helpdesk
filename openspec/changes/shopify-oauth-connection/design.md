## Context

See `proposal.md` for the motivation and ADR 0070 for the decision. The facts that shape the approach.

**The connection today** (overlay, branch base `feat/overlay-foundation`):
- One row per account in `inclamo_shopify_connections` (`custom/db/migrate/20261105100000_create_inclamo_shopify_connections.rb`) with `auth_kind`, `client_id`, encrypted `client_secret` and `access_token`, `token_expires_at`, `scopes`, `customer_data_mode`, `status`. Two kinds exist, `client_credentials` and `legacy_token` (`custom/app/models/inclamo/shopify_connection.rb:7`); secrets are encrypted and a save without encryption keys is refused (`:20-23`, `:52-54`); `status` is `working` or `broken` (`:25`).
- `Inclamo::Shopify::StoreConnection` is the only door to the store: it hands out a token, renews a 24-hour token five minutes before it expires under a Redis lock so one process renews at a time, retries a refused request once with a fresh token and then marks the connection broken (`custom/lib/inclamo/shopify/store_connection.rb`). `TokenExchange` posts to the store's `/admin/oauth/access_token` (`custom/lib/inclamo/shopify/token_exchange.rb:15-18`). `Verifier` reads the shop, the scopes, the customer data mode and the store's answer to its orders.
- The administrators' endpoint is `api/v1/accounts/:account_id/inclamo/shopify/connection` with `create`, `recheck`, `destroy` (`custom/config/routes.rb`, `custom/app/controllers/api/v1/accounts/inclamo/shopify_connections_controller.rb`); its `present` never carries a secret. The dialog is ours, `shims/app/javascript/dashboard/inclamo/components/ConnectDialog.vue`.
- The store's base URL can be pointed at the test proxy only when `INCLAMO_E2E=1` (`custom/lib/inclamo/shopify.rb:20-21`); a domain must match `\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z` (`:10`).

**Chatwoot v4.19.1** (paths relative to Chatwoot's tree):
- `ApplicationController` is an `ActionController::Base` (`app/controllers/application_controller.rb:1`) and `Api::BaseController` inherits it (`app/controllers/api/base_controller.rb:1`), so our API endpoint can set an encrypted cookie and a plain controller of ours can serve a page.
- The overlay's routes are prepended into Chatwoot's route set (`custom/config/overlay.rb:37-40`), so routes outside `/api` are ours to add.
- `Redis::Alfred.set(key, value, nx:, ex:)` and `delete` (`lib/redis/alfred.rb:10`, `:28`).
- Scheduled jobs: Chatwoot loads `config/schedule.yml` into sidekiq-cron (`config/initializers/sidekiq.rb:74-90`); the overlay adds its own with `Sidekiq::Cron::Job.create` from `custom/config/overlay.rb`, as `sla-timers` does.
- `Chatwoot.encryption_configured?` (`config/application.rb:101`).

**Shopify** (read on 2026-11-07):
- The authorization code grant of a non-embedded app: the app redirects to the store's `/admin/oauth/authorize` with `client_id`, `scope`, `redirect_uri` (which must exactly match one configured for the app) and a random `state`; on the callback the app checks the state, removes `hmac` from the query, sorts the rest, computes a hex HMAC-SHA256 with the client secret and compares in constant time, and checks the shop against an anchored `myshopify.com` pattern; then it posts `client_id`, `client_secret`, `code` and `expiring=1` to `/admin/oauth/access_token` and gets `access_token`, `scope`, `expires_in` 3600, `refresh_token`, `refresh_token_expires_in` 7776000. A granted `write_*` scope includes its `read_*` and may be listed alone. (https://shopify.dev/docs/apps/build/authentication-authorization/authenticate-standalone-apps)
- Refresh: `grant_type=refresh_token` with the client ID and secret returns a new access token and a new refresh token with a new 90-day expiry; the presented refresh token stays usable until the new one is used, at most 30 days from its first use; refresh one store at a time; on a timeout, a network error or a 5xx, retry with the refresh token still held. (https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens, https://shopify.dev/docs/apps/build/authentication-authorization/implement-token-exchange)
- Expiring offline tokens are required of new public apps since 2026-04-01 and of all public apps from 2027-01-01; custom apps are not affected. (https://shopify.dev/changelog/posts/expiring-offline-access-tokens-required-for-all-public-apps-as-of-january-1-2027) The code grant asks for them with `expiring=1`. (https://shopify.dev/docs/apps/build/authentication-authorization/migrate-to-expiring-offline-access-tokens)
- Distribution: custom distribution installs on one store, the stores of one Plus organization, or development stores, without approval; public distribution needs approval; the method cannot be changed once chosen; custom distribution gives an install link for the store owner. (https://shopify.dev/docs/apps/launch/distribution, https://shopify.dev/docs/apps/launch/distribution/select-distribution-method)
- Protected customer data: both levels always available to a custom app, review required for a public app. (https://shopify.dev/docs/apps/launch/protected-customer-data)
- Webhooks: `X-Shopify-Hmac-SHA256` is a base64 HMAC-SHA256 of the raw body with the client secret; each delivery has an ID for de-duplication. (https://shopify.dev/docs/apps/build/webhooks/verify-deliveries) The three compliance topics are required of apps distributed through the App Store; an invalid HMAC must get `401`. (https://shopify.dev/docs/apps/build/compliance/privacy-law-compliance)
- An app that implements the code grant itself declares its scopes in the authorization URL's `scope` (https://shopify.dev/docs/apps/build/authentication-authorization/manage-access-scopes); an app under Shopify managed installation takes them from its configuration instead, and `use_legacy_install_flow = true` keeps an app on the per-request flow (https://shopify.dev/docs/api/shop/guides/creating-a-client).

## Goals / Non-Goals

**Goals:**
- A merchant connects with one button and Shopify's screen; nothing else about the connection changes for the panel or the actions.
- One token code path that is already what a public app needs (expiring tokens, refresh, rotation).
- Every request from or via Shopify verified before it changes anything.
- The routes and the app configuration shared with `shopify-sign-in`, so the second change adds handlers, not a second app.

**Non-Goals:**
- A public app, its listing and review; acting on compliance requests; an embedded app in the Shopify admin.
- Changing how a connection made with credentials works.

## Decisions

**D1. One connection, a third way in.** `auth_kind` gains `shopify_app`. `inclamo_shopify_connections` gains `refresh_token` (encrypted), `refresh_token_expires_at` and `inclamo_shopify_app_id`; `status` gains `removed` (the app was uninstalled at the store). Everything that reads a store keeps going through `StoreConnection`, which learns a third renewal (D6). *Alternative:* a separate table for OAuth connections. Rejected: "one store per account", the panel, the actions and removal would each have to look in two places.

**D2. The operator's app per account.** Table `inclamo_shopify_apps`: account (unique), `client_id`, `client_secret` (encrypted), `shop_domain` (the one store a custom-distribution app is for), `distribution` (`custom`; `public` reserved). Set by `rake inclamo:shopify:app ACCOUNT=<id> SHOP=<domain> CLIENT_ID=<id>`, which reads the secret from standard input so it lands in no shell history, refuses without encryption keys, and prints the App URL and redirection URL to enter in the app's settings. Per account, as `docs/spec-plan.md` §5 asks. *Alternatives:* instance environment variables (rejected now: per instance, not per account; it may come back as the default of a public app); a super-admin page (later: Chatwoot's super-admin dashboards are its own, a page there is a seam).

**D3. Routes, shared with `shopify-sign-in`.**
- `POST api/v1/accounts/:account_id/inclamo/shopify/connection/authorize` (administrators): body `purpose` = `connect` or `update_permissions`; answers the Shopify authorization URL and sets the state cookie (D4). The dialog then navigates the top window there.
- `GET /inclamo/shopify/app`: the App URL. Shopify sends the store's user here when the app is installed from its link and when it is opened from the Shopify admin. After D5's checks: an assigned account without a connection starts a `connect` flow; a connected one goes to the **launch handler**, which this change ships as "redirect to the helpdesk's sign-in page" and `shopify-sign-in` replaces; no assigned account renders the "not set up for this store" page.
- `GET /inclamo/shopify/callback`: the one allowed redirection URL. It dispatches on the state's purpose: `connect` and `update_permissions` here; `sign_in` is registered by `shopify-sign-in`. An unknown purpose is refused like an unknown state.
- `POST /inclamo/shopify/webhooks`: one address for every topic, the topic read from `X-Shopify-Topic` (D7).

What belongs to which change: this change owns the app record, the four routes, the state store with its purposes, the request checks of D5, the webhook endpoint, and the launch handler's seam with its default. `shopify-sign-in` adds the `sign_in` purpose (an online-mode authorization), the launch handler for a connected store, and the "Sign in with Shopify" button on Chatwoot's login page. The app needs no setting for sign-in beyond what this change documents.

**D4. The state.** A random 32-byte nonce. Redis key `inclamo:shopify:oauth:<nonce>` with purpose, account, the starting user (when started in the helpdesk), shop, `return_to` (a same-origin path) and the time, set with `nx` and a 600-second expiry. The same nonce in an encrypted, `HttpOnly`, `Secure`, `SameSite=Lax` cookie `inclamo_shopify_oauth`. The callback requires both to match, then deletes the key, so a state works once and only in the browser that started it. `Lax`, not `Strict`: Shopify's redirect is a top-level navigation from another site, which `Strict` would strip. *Alternative:* a signed state without storage. Rejected: it cannot be used only once.

**D5. Order of checks** on the callback and on the app address: the shop matches the domain pattern; an operator app is meant for that shop; the HMAC over the sorted query without `hmac`, hex, constant-time, with that app's secret; on the callback, the state of D4 and its shop equal to the query's; then the code exchange with `expiring=1` through the overlay's HTTP client with its 10-second limit; then the granted scopes, a `write_*` counting as its `read_*`; then the existing `Verifier` with the new access token (shop, mandatory read scopes, customer data mode, the store's answer to its orders); then one transaction that saves the connection, deletes earlier credentials of the same store (the switch of the spec) and records the state's purpose. Any failure stops there and saves nothing. Each refusal renders our page with a code and a sentence, never a token or a secret.

**D6. Renewal.** `StoreConnection#renew!` gains the `shopify_app` branch: `grant_type=refresh_token` with the account app's ID and secret, under the existing Redis lock (which is Shopify's "one store at a time"). The new pair is saved in one update; until then the old refresh token stays, so a lost answer is retried with it. A timeout, a network error or a 5xx is retried with the same refresh token; a `400` or `401` marks the connection broken and the dialog offers "Reconnect with Shopify" (a `connect` flow). `Inclamo::ShopifyTokenRenewalJob`, registered from `custom/config/overlay.rb` like `sla-timers`'s job, runs daily and renews every `shopify_app` connection whose refresh token expires within seven days. *Alternative:* renew only on use. Rejected: an account nobody opens for ninety days would fall out.

**D7. Webhooks.** The shop comes from `X-Shopify-Shop-Domain`; its operator app's secret verifies `X-Shopify-Hmac-SHA256` over the raw body; an unknown shop or a mismatch answers `401`. A delivery ID already seen within a day is answered `200` and ignored (the header names are confirmed on the first recorded delivery, task 7.3). `app/uninstalled`: tokens set to nil, `status` `removed`. `app/scopes_update`: `recheck!`. `customers/data_request`, `customers/redact`, `shop/redact`: a row in `inclamo_shopify_compliance_requests` (topic, shop, Shopify's request ID when present, received at; no customer data), answered `200`. The subscriptions are declared in the app's configuration by the operator (`docs/operator-shopify-app.md`), not created through the API, because the compliance topics can only be declared there and one place is easier to check.

**D8. One scope list.** `Inclamo::Shopify::SCOPES` holds the list of `docs/connect-shopify.md`; a change that needs another scope adds it there and to that document. For a `shopify_app` connection, `SCOPES` minus the granted scopes is reported as `missing_scopes`; when it is not empty the dialog shows "Update permissions" (an `update_permissions` flow with the full list), and the actions keep their existing "missing scope" state. A connection made with credentials is unchanged: its merchant edits their own app.

**D9. Where the flows end.** A flow started in the dashboard ends with a redirect to its `return_to` with `?inclamo_shopify=<result>`, which `OrdersSection.vue` reads to show a one-line message and then drops from the address. A flow started at the app address ends on a small page of our own (`custom/app/views/inclamo/shopify/`, the view path prepended by our controller): connected, refused with the reason, or not set up for this store, each with a link to the helpdesk. No Chatwoot dashboard seam.

**D10. The dialog.** The connection's `present` gains `operator_app` (the shop domain only, or null), `missing_scopes` for a `shopify_app` connection, and `status` `removed`. `ConnectDialog.vue`: with an operator app, "Connect with Shopify" first and "Use your own app's credentials" as the second way; `removed`: the sentence and "Connect with Shopify"; `broken` on a `shopify_app` connection: "Reconnect with Shopify"; missing scopes: "Update permissions". Agents see the states without the buttons, as today.

**D11. Testing without Shopify's screen.** In the end-to-end stack the test proxy stands in for the two Shopify addresses of the flow, nothing else:
- `GET /admin/oauth/authorize` answers `302` to the `redirect_uri` with `code`, `shop`, `state`, `timestamp`, `host` and an `hmac` computed with the e2e app's secret (given to the proxy in its environment), or with `error=access_denied` when a rule says decline.
- `POST /admin/oauth/access_token` with a `code` answers an expiring pair whose access token is a real token of the test store, obtained by the client credentials grant of the e2e app, so the panel reads real orders; with `grant_type=refresh_token` it answers a new pair. Rules: refuse a refresh, list only `write_*` scopes, shorten `expires_in`.
- The tests post webhooks themselves, signed with the e2e app's secret.
- `e2e/setup.rb` gives the e2e account an operator app through the rake task.

The browser reaches the proxy because the base URL override applies under `INCLAMO_E2E=1` only. Shopify's real consent screen is covered by one recorded run on a development store (task 7.2). "Installation without encryption keys" joins the existing `ELSEWHERE` entry of `scripts/check-e2e-coverage.mjs`, covered by the rake task's spec.

## Risks / Trade-offs

- [One app per merchant to keep in the operator's Partner organization] → the operator guide names the app after the store, and the rake task prints the URLs to enter, so a mistyped URL shows up at the first install.
- [A custom-distribution app can never become public] (Shopify: the method cannot be changed) → a public app will be a new app; an account moves to it by "Connect with Shopify" again, which D1 and D2 already allow.
- [Installing from Shopify connects without a helpdesk sign-in] → only to the account the operator assigned to that store, only after Shopify's signature and Shopify's own consent screen; the connection records that it was made from Shopify.
- [A refresh token lost between Shopify's answer and our save] → the old token stays until the new pair is saved, and Shopify keeps the presented token usable for up to 30 days.
- [The stand-in for Shopify's screen could drift from Shopify] → it reproduces only the documented parameters, and the recorded run on a development store is repeated before each release that touches this flow.
- [Compliance requests are recorded, not acted on] → acceptable for custom distribution; the public app needs a change of its own that acts on them.

## Migration Plan

One additive migration (two tables, three columns, the new enum values), with a version no other branch uses. Existing connections are untouched. Without an operator app nothing new is visible, so the release can go out before any app is set. Rollback: remove the app rows; `shopify_app` connections fall back to "not connected" and the credentials form stays.

## Open Questions

- The wording of the two buttons ("Connect with Shopify" and "Use your own app's credentials") may change after the founder's UI pass; it changes no requirement.
