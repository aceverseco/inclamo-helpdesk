## 1. Alignment and facts

- [ ] 1.1 Confirm with `shopify-oauth-connection` as built (D1): the shared callback `/inclamo/shopify/callback` and its purpose registry, the state store's key and cookie, the launch handler seam at `/inclamo/shopify/app`, `auth_kind: shopify_app`, and the stand-in OAuth endpoints of D11 built once for both; verify both designs name the same paths, purpose, kind and seam, and correct D1 where the built code differs
- [ ] 1.2 Check by hand on a development store with a real staff account and the app installed, and record in design D4 with the date and the parameters seen (secrets and personal data removed): whether the per-user authorization of an installed app prompts or returns at once; what Shopify sends to the callback when the person declines and when a staff member without access to the app tries; what a staff member removed from the store sees; whether Shopify notifies an app when a staff member is removed; that a launch from the admin carries `shop` and `hmac`; verify each observation by a dated note in the design and the matching rule in the stand-in of D11

## 2. Backend

- [ ] 2.1 Add the routes `/inclamo/shopify/sign_in/available` and `/inclamo/shopify/sign_in` outside the account API and register the `sign_in` purpose with the shared callback (D1); verify by routing specs, a callback spec that a `sign_in` state reaches this change's handler, and that Chatwoot's `/shopify/callback` and `webhooks/shopify` still route to Chatwoot's controllers
- [ ] 2.2 Answer availability (D2, D8); verify by request specs: no store connected, a store connected with the merchant's own credentials, one store connected through the app, two accounts connected through the app, the app's credentials missing; and that the answer names no store
- [ ] 2.3 Start a sign-in (D3): a `sign_in` state through the shared store, the authorize URL with `grant_options[]=per-user`, the granted scopes and `/inclamo/shopify/callback`; verify by request specs on the redirect's host, path and parameters, on the state's purpose, shop, account and entry, and that a start without a store connected through the app redirects to the login page with `not_connected`
- [ ] 2.4 Handle a `sign_in` callback in the order of D4; verify by request specs for Shopify's refusal, the store disconnected since the start, the exchange refused, the exchange not answered within 10 s and an offline token in the answer (each redirects with its code and creates no session, user or account), and that the shared checks refuse a `sign_in` state of another browser, the same state twice, a wrong `hmac` and another shop before this change's handler runs
- [ ] 2.5 Decide who gets in (D5); verify by specs: a verified agent, an email in other letter case, an unverified email, a collaborator, an unknown email, a user of another account (same code as unknown), a user with two-factor on, a deactivated user, an invited user who has not accepted (confirmed, no password set), the account owner treated as anyone; and with sign-up allowed on the installation, that no user and no account are created
- [ ] 2.6 Hand off to Chatwoot's one-time link (D6); verify by a request spec that follows the redirect, posts the link's token to `/auth/sign_in`, gets a session whose dashboard opens the store's account, and that the token works once; verify that the online token appears in no table, no Redis key and no log line
- [ ] 2.7 Plug the launch handler for a connected store into the seam of `shopify-oauth-connection` (D2); verify by request specs on `/inclamo/shopify/app` with a valid launch of a connected store (a sign-in starts with `entry: admin_launch`) and with a store that is not set up (that change's page, nothing started)
- [ ] 2.8 Write the log line of D9 and add `code`, `hmac` and `state` as exact filtered keys; verify by specs reading the log after a success and after each refusal: one line each, the outcome and ids present, no email, name, Shopify user id, token or code; and that a parameter such as `country_code` is still logged
- [ ] 2.9 Count attempts per address (D10); verify by request specs that the eleventh start or callback within five minutes redirects with `too_many`, that the count resets after the period, and that `INCLAMO_SHOPIFY_SIGN_IN_LIMIT` changes the limit

## 3. Login page

- [ ] 3.1 Pick the patch number after checking every branch's `patches/` (D7); write the patch `login-methods` with the empty `app/javascript/v3/extensions/loginMethods.js` and its use in `Index.vue`; verify `scripts/assemble.sh` applies every patch on a clean v4.19.1 tree and Chatwoot's own `Index.spec.js` passes
- [ ] 3.2 Build `ShopifySignInButton.vue` and register it in the overlay's shim for `v3/extensions/loginMethods.js` (D7, D8); verify by component tests: available (button and divider shown), not available (nothing rendered, no divider of ours), each error code's message, and the error parameter removed from the address after it is shown
- [ ] 3.3 Add the strings and settle the button's label with Shopify's brand rules (Open Questions); verify `scripts/check-ui-strings.mjs` passes and the design records the label

## 4. End to end

- [ ] 4.1 Add the stand-in for Shopify's authorization to `e2e/proxy/server.mjs` (D11) with the rules `oauth_user`, `oauth_refused`, `oauth_exchange_fails` and `oauth_wrong_hmac`, the test app's secret passed to the proxy by the e2e stack only, and `INCLAMO_SHOPIFY_SIGN_IN_LIMIT` raised there; verify by a small test of the proxy that its redirect's `hmac` verifies with that secret and that a rule changes the answer
- [ ] 4.2 Add `shopify-sign-in` to the coverage check's map with `e2e/tests/shopify-sign-in.spec.mjs`, and put the two scenarios the stack cannot show (the log line, too many attempts) in its list of scenarios covered elsewhere, naming their request specs; verify `scripts/check-e2e-coverage.mjs` lists every scenario of the spec
- [ ] 4.3 Write the tests named after the scenarios: the login page in a browser, Shopify as the stand-in, the dashboard after sign-in; verify they pass on the stand
- [ ] 4.4 Run the full suite in CI on an `e2e/**` branch; verify every test passes and the log holds no token-shaped string and no email of the test staff members

## 5. Guide

- [ ] 5.1 Add "Signing in with Shopify" to the merchant's guide of `shopify-oauth-connection`: who can sign in this way, what each refusal on the login page means, that removing a person from the Shopify store does not remove them from the helpdesk; verify the section names every message of D7
