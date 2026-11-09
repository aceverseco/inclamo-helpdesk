## Context

See `proposal.md` for motivation and ADR 0070 for the decision. Facts that shape the approach, read in Chatwoot v4.19.1 (paths relative to Chatwoot's tree) and in Shopify's documentation on 2026-11-07:

- **Chatwoot signs a person in after an outside sign-in by a one-time link.** Its OAuth callback looks the user up by email (`app/controllers/devise_overrides/omniauth_callbacks_controller.rb:125-128`), then redirects to `/app/login?email=…&sso_auth_token=…&sso_account_id=…` (`:14-32`, `:68-74`). The token is 32 random bytes kept in Redis for five minutes (`app/models/concerns/sso_authenticatable.rb:4-9`). The login page submits it at once (`app/javascript/v3/views/login/Index.vue:155-158`); the sessions controller accepts it (`app/controllers/devise_overrides/sessions_controller.rb:64-76`, `:104-113`), applies the session limit (`:69`, `:115-144`), creates Chatwoot's own token (`:84-95`) and records the session (`:30`). That session lasts two months (`config/initializers/devise_token_auth.rb:10`). `sso_account_id` makes the dashboard open that account (`app/javascript/v3/helpers/AuthHelper.js:87-96`).
- **Chatwoot's callback creates an account for an unknown email** when sign-up is allowed (`omniauth_callbacks_controller.rb:9`, `:50-66`, `:137-151`), and confirms an unconfirmed user and gives them a random password (`:14-21`, `:153-160`).
- **The one-time link skips the second factor.** Two-factor and device checks run only on the password path (`app/controllers/concerns/device_verification_guard.rb:4-23`, called from `sessions_controller.rb:23`); the link path returns before it (`:22`). A user has `mfa_enabled?` (`app/models/user.rb:216`).
- **Users are found by email in lower case** (`user.rb:199-201`) and belong to accounts through `account_users` (`user.rb:87-88`).
- **Chatwoot has its own Shopify integration** with routes `/shopify/callback` and `webhooks/shopify` (`config/routes.rb:731`, `:744-746`) behind `ENABLE_SHOPIFY_INTEGRATION` (`app/services/shopify/feature_gate.rb`). Our routes must not collide with it. Its bundle has OmniAuth strategies for Google and SAML only (`Gemfile:184-192`).
- **The login page** shows Google and SAML buttons and an "or" divider above the form (`Index.vue:468-493`), driven by `window.chatwootConfig.allowedLoginMethods` (`app/views/layouts/vueapp.html.erb:45`, `app/controllers/dashboard_controller.rb:109-114`). It maps a few `?error=` codes to messages and shows a generic one for any other (`Index.vue:26-32`, `:159-176`). The `v3` alias points at its sources (`vite.shared.ts:7`). It has no hook for extra methods.
- **Rate limits.** Rack::Attack runs only in production (`config/initializers/rack_attack.rb:407`); `/auth/sign_in` is throttled per address (5 in 5 minutes) and per email (10 in 15 minutes) (`:151-163`). The end-to-end stack turns it off (`dev/docker-compose.e2e.yaml`).
- **Logs** filter keys containing `token`, `secret`, `password` and a few more (`config/initializers/filter_parameter_logging.rb:4-13`), not `code`, `hmac` or `state`.
- **Shopify.** A standalone app authenticates with the authorization code grant: the app redirects to `https://{shop}/admin/oauth/authorize` with `client_id`, `scope`, `redirect_uri` (exactly one of the app's redirect URLs) and a random `state`; the callback must check `state`, the `hmac` of the other query parameters (SHA-256 with the client secret, compared in constant time) and the shop's format, then exchange the code at `/admin/oauth/access_token` (shopify.dev/docs/apps/build/authentication-authorization/authenticate-standalone-apps). Appending `grant_options[]=per-user` makes the exchange return an online token with `associated_user` (`id`, `email`, `email_verified`, `account_owner`, `collaborator`, names, locale) and `associated_user_scope`; one request returns one kind of token, and an online token has no refresh token (same page). An online token expires after 24 hours or when the person logs out of the admin; `email` is always present and is to be trusted only when `email_verified` is true; if the app is not installed yet, the installing person must have every scope (shopify.dev/docs/apps/build/authentication-authorization/access-tokens).
- **The overlay** reaches Shopify through `Inclamo::Shopify.base_url`, which the end-to-end stack points at its proxy (`custom/lib/inclamo/shopify.rb:16-24`); the store connection is `Inclamo::ShopifyConnection`, one per account (`custom/app/models/inclamo/shopify_connection.rb`).

## Goals / Non-Goals

**Goals:**
- A staff member of the connected store who is a user of its helpdesk account signs in with one click, from the login page or from the Shopify admin.
- Nobody else gets in this way, and nothing is created by trying.
- Nothing from Shopify outlives the sign-in: no token stored, nothing personal logged.
- Every scenario runs end to end without a real Shopify login.

**Non-Goals:**
- Using the staff member's permissions inside the helpdesk (roles stay the helpdesk's).
- Keeping the helpdesk session in step with the Shopify session.
- Sign-in for Chatwoot's super admin console or its mobile apps.

## Decisions

**D1. One app, one namespace, two changes.** Both changes use the same Shopify app and the same addresses under `/inclamo/shopify/`, clear of Chatwoot's `/shopify/`. `shopify-oauth-connection` owns the app record and its secret, the App URL `GET /inclamo/shopify/app`, the one redirection URL `GET /inclamo/shopify/callback` that dispatches on the state's purpose, the state store (`inclamo:shopify:oauth:<nonce>` in Redis with the cookie `inclamo_shopify_oauth`, ten minutes, used once), its checks of the shop, the `hmac` and the state, the webhooks, and the connection kind `auth_kind: shopify_app` ("through the app"); it ships a launch handler seam whose default redirects a connected store to the helpdesk's sign-in page (its design D3–D5). This change owns: `GET /inclamo/shopify/sign_in/available` (D8); `GET /inclamo/shopify/sign_in`, the start (D3); the `sign_in` purpose of the shared callback (D4); the launch handler for a connected store, which replaces that default (D2); the button (D7); and D5, D6. The app needs no redirection URL beyond the one callback. Task 1.1 confirms the names when both are built.

**D2. The store comes from the instance or from the launch, never from the person.**
- From the login page: the one account whose store is connected through the app. With none, or with more than one (assumption 8), there is no button and the start refuses with `not_connected`.
- From the Shopify admin: `/inclamo/shopify/app` checks the shop and Shopify's signature (the other change's D5) and, for a connected store, calls this change's launch handler, which starts a sign-in for that shop with `entry: admin_launch`. A shop that is not set up gets the other change's "not set up for this store" page.
Alternative rejected: a shop field. It lets anyone probe which stores an instance serves, and the merchant's team does not need it.

**D3. Starting.** The start writes a state through the shared store with purpose `sign_in`, the shop, the account and the entry, and sends the browser to `{base_url(shop)}/admin/oauth/authorize` with the app's `client_id`, `scope` set to the scopes the store granted (so Shopify does not ask the owner to approve anything new), `redirect_uri` `{FRONTEND_URL}/inclamo/shopify/callback`, the `state` and `grant_options[]=per-user`. Alternative rejected: an OmniAuth Shopify strategy in Chatwoot's OmniAuth stack. It is a new gem, and its success path is Chatwoot's callback, which creates accounts (Context).

**D4. The callback for `sign_in`, checked in this order; the first failure ends it.** The shared callback has already checked the shop's format, the `hmac`, the state (this browser, ten minutes, once) and that the state's shop is the query's; its refusals (`expired` for a state that is unknown, used or of another browser; `invalid` for a wrong `hmac` or shop) are its own page, because an unknown state names no purpose. For a valid `sign_in` state, each failure below redirects to `/app/login?inclamo_shopify_error=<code>` and records its code (D9); nothing is created.
1. Shopify reported an error or a refusal instead of a code: `shopify_refused`. What Shopify sends here is verified on a development store (task 1.2).
2. The store no longer connected through the app (disconnected or uninstalled since the start): `not_connected`.
3. The code exchange at `{base_url(shop)}/admin/oauth/access_token`, without `expiring` (an online token has no refresh token), refused, failed or not answered within 10 seconds: `shopify_unavailable`.
4. The answer has no `associated_user` (an offline token): `invalid`.
Then the access token in the answer is dropped. It is never written to the database, Redis or a log, and nothing calls Shopify with it.

**D5. Who gets in.** In this order, each a refusal code:
1. `email_verified` not true: `email_not_verified`.
2. `collaborator` true: `collaborator` (assumption 3).
3. No user with that email (case-insensitive), or a user who is not a member of the store's account: `not_a_user`. One code and one message for both, so the page does not tell which emails exist.
4. The user has two-factor authentication on: `two_factor` (assumption 4).
5. The user cannot sign in for another reason Chatwoot knows (`active_for_authentication?` false, other than a pending confirmation): `not_a_user`.
A user whose invitation is still pending is confirmed, as Chatwoot does after Google sign-in, without a password being set (assumption 5). `account_owner` changes nothing (assumption 2).

**D6. The hand-off is Chatwoot's one-time link.** The service calls `generate_sso_auth_token` on the user and redirects to `/app/login?email=…&sso_auth_token=…&sso_account_id=<store's account>`. From there Chatwoot does everything (Context): the session, its limit, its list, two months of life. The online token's 24 hours do not matter, because the helpdesk never uses it. Alternative rejected: creating the Chatwoot session in our callback. It would copy the sessions controller's limit and tracking and fall behind it on every upstream release.

**D7. The login-page seam.** A new patch `login-methods` (its number is the next free one when it is built; 0006 at the time of writing, unless `shopify-oauth-connection` takes it first). It adds `app/javascript/v3/extensions/loginMethods.js`, which exports an empty list in Chatwoot, and makes `Index.vue` show, above its own buttons, every entry whose `available()` resolves to true, and show the "or" divider when any button is shown. An entry is `{ name, component, available: () => Promise<boolean> }`. The overlay's shim registers `ShopifySignInButton.vue`, whose `available()` reads D8. The button is a link to the start; it reads `?inclamo_shopify_error=` and shows our message for each code of D4, D5 and D10 (`shopify_refused`, `expired`, `invalid`, `not_connected`, `shopify_unavailable`, `email_not_verified`, `collaborator`, `not_a_user`, `two_factor`, `too_many`) above itself, so Chatwoot's error map stays as it is. Strings come from the overlay's catalogue and pass `scripts/check-ui-strings.mjs`.

**D8. Availability.** `GET /inclamo/shopify/sign_in/available` answers `{ "available": true }` or `false`, nothing else: true when exactly one account has a store connected through the app and the app's credentials are configured. It names no store.

**D9. One line per attempt, nothing personal.** `inclamo.shopify_sign_in` with `outcome` (`signed_in` or a code of D4 and D5), `entry` (`login_page` or `admin_launch`), `account_id`, `user_id` when a user was found, and `owner` and `collaborator` when Shopify answered. Never the email, names, the Shopify user id, the token or the code. `code`, `hmac` and `state` are added to the filtered parameters as exact keys, unless `shopify-oauth-connection` has added them already (`/\A(code|hmac|state)\z/`), so other keys that contain "code" stay readable in logs.

**D10. Rate limits.** A counter of our own in Redis per address: 10 requests to the start and to the shared callback with a `sign_in` state together in 5 minutes; the eleventh is answered with a redirect to the login page with `too_many`, and the button says there were too many attempts. The limit is read from `INCLAMO_SHOPIFY_SIGN_IN_LIMIT` (default 10); the end-to-end stack raises it, because every test signs in from one address. The link's own `POST /auth/sign_in` also counts against Chatwoot's login throttles when Rack::Attack is on (Context). Alternative rejected: a Rack::Attack throttle. Its answer is one 429 page for every throttle of the application, not a message on the login page, and it runs only in production.

**D11. A stand-in for Shopify's authorization in the end-to-end proxy** (`e2e/proxy/server.mjs`). `GET /admin/oauth/authorize` answers with a redirect to `redirect_uri` carrying a code, the shop, the state, a timestamp and an `hmac` signed with the test app's secret (given to the proxy in the e2e stack only). `POST /admin/oauth/access_token` answers an online token for the staff member set by a rule `oauth_user` (`email`, `email_verified`, `collaborator`, `account_owner`). Rules `oauth_refused` (a refusal instead of a code), `oauth_exchange_fails` (a status) and `oauth_wrong_hmac` cover the failures. The browser reaches the proxy because `base_url` points there in the e2e stack. `shopify-oauth-connection` needs the same two endpoints for its install, with an offline token; whichever change is built first adds them. Shopify's real consent screen cannot be driven by the tests (a real staff login); it is checked once by hand on a development store (task 1.2).

## Risks / Trade-offs

- [The email travels in the login URL] Chatwoot's one-time link carries `email=` in the query, so it is in the browser's history and the request log of the login page → it is the same as Chatwoot's Google sign-in; avoiding it is a core change, not taken.
- [Pressing the button reveals the store's Shopify address] the browser goes to `https://{shop}/admin/oauth/authorize` → on a merchant's own helpdesk the store is no secret; D8 says only yes or no.
- [Removal in Shopify is not seen at once] the helpdesk learns nothing when a staff member is removed from the store, and an open session lasts up to two months → the guide tells administrators to remove the person in the helpdesk too (assumption 7); whether Shopify notifies apps of staff removal is checked in task 1.2.
- [This way in skips the helpdesk's second factor] → refused for users who have it on (assumption 4); for the rest, Shopify's own login, with its two-step verification when the staff member uses it, is what protects this way in.
- [A seam in the login page, which Chatwoot changes often] → the patch adds one import, one list and one condition; `scripts/assemble.sh` applies it on every upstream release, and Chatwoot's login spec runs after it.
- [The app's secret signs every callback] a leak lets anyone forge a callback's `hmac` → still not a sign-in: the state must match this browser's cookie and Redis, and the code must be exchanged with Shopify; the secret itself is `shopify-oauth-connection`'s to keep.
- [Shopify asks the owner to approve scopes again] if the start asks for scopes the store did not grant → the start asks for exactly the granted scopes (D3).

## Migration Plan

Nothing to migrate: no table, Redis records of ten minutes. The button appears once a store is connected through the app. Rollback: remove the overlay code and the patch; password sign-in is untouched, and sessions made through Shopify stay valid until they end.

## Open Questions

- The button's label ("Sign in with Shopify") and Shopify's brand rules for it; settled with the strings in task 3.3.
