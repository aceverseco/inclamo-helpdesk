## 1. Data and configuration

- [ ] 1.1 Pick a migration version after checking every worktree's `custom/db/migrate` and the stand's spec sources; add `inclamo_shopify_apps`, `inclamo_shopify_compliance_requests`, the columns `refresh_token` (encrypted), `refresh_token_expires_at` and `inclamo_shopify_app_id` on `inclamo_shopify_connections`, the auth kind `shopify_app` and the status `removed` (D1, D2); verify by model specs: one app per account, the secret and the refresh token encrypted, a save refused without encryption keys, a `removed` connection holding no token
- [ ] 1.2 Add `Inclamo::Shopify::SCOPES` from `docs/connect-shopify.md` and the rule that a `write_*` scope counts as its `read_*` (D8); verify by specs for a grant listing `write_orders` without `read_orders`, and for `missing_scopes` of a `shopify_app` connection
- [ ] 1.3 Write `rake inclamo:shopify:app` (D2): secret from standard input, refusal without encryption keys, a second run replaces the app, prints the App URL and the redirection URL; verify by a task spec that the secret is stored encrypted and never printed, and that the refusal leaves nothing

## 2. The consent flow

- [ ] 2.1 Write the state store of D4 (Redis key with expiry, encrypted `SameSite=Lax` cookie, one-time consume, purposes); verify by specs for a used state, a cookie of another browser, a state 601 seconds old and an unknown purpose
- [ ] 2.2 Write the request checks of D5 (shop pattern, operator app for the shop, HMAC over the sorted query in constant time); verify by specs with a correctly signed query, a changed value, an added parameter, another app's secret and `x.myshopify.com.example.org`
- [ ] 2.3 Write the code exchange with `expiring=1` over the overlay's HTTP client with its 10-second limit; verify by specs on recorded answers: `200` with an expiring pair, `400`, a timeout
- [ ] 2.4 Add `POST inclamo/shopify/connection/authorize` for administrators with the purposes `connect` and `update_permissions` (D3); verify by request specs that the answer is an authorization URL with the app's client ID, the full scope list, the redirection URL and a state, that an agent is refused as forbidden, and that an account without an operator app is refused
- [ ] 2.5 Write the callback for `connect` and `update_permissions` in the order of D5, one transaction, the switch from credentials of the same store, the refusal of another store, a declined consent, `return_to` limited to same-origin paths; verify by request specs for every scenario of "An administrator connects the store through Shopify's consent", "Every redirect from Shopify is verified before anything is kept" and "One store connection, two ways into it"
- [ ] 2.6 Write the app address with the launch handler seam and its default (D3); verify by request specs for the three scenarios of "Installing the app from Shopify connects the account assigned to that store", and by a spec that registers a test handler in place of the default
- [ ] 2.7 Write the pages of D9 with the view path prepended by our controller; verify by request specs that each page names its outcome and holds no token or secret

## 3. Tokens

- [ ] 3.1 Add the `shopify_app` renewal to `StoreConnection` (D6): refresh grant, the new pair saved in one update, a retry with the same refresh token on a timeout or a 5xx, broken on `400` or `401`; verify by specs: an expired access token renewed, a `503` then `200` keeping the old refresh token until the new pair is saved, a `401` marking the connection broken, two processes renewing once
- [ ] 3.2 Write `Inclamo::ShopifyTokenRenewalJob` and register it daily from `custom/config/overlay.rb` as `sla-timers` does; verify by specs that it renews only `shopify_app` connections whose refresh token expires within seven days, and that the job is registered only in a Sidekiq server

## 4. Webhooks

- [ ] 4.1 Add `POST /inclamo/shopify/webhooks` with the HMAC over the raw body (base64), `401` for an unknown shop or a mismatch, and de-duplication by delivery ID (D7); verify by request specs: a valid delivery, a changed body, an unknown shop, the same delivery twice
- [ ] 4.2 Handle `app/uninstalled`; verify by specs that the tokens are gone, the status is `removed`, earlier order action records stay, and a second notice changes nothing
- [ ] 4.3 Handle `app/scopes_update` with a check again; verify by a spec that the scopes and the available actions follow the store
- [ ] 4.4 Record the three compliance topics; verify by specs that the row holds topic, shop and time and no customer field, and that a wrong signature gets `401`

## 5. Dashboard

- [ ] 5.1 Extend the connection's `present` with `operator_app`, `missing_scopes` and the `removed` status (D10); verify by request specs for each state that no secret or token appears
- [ ] 5.2 Extend `ConnectDialog.vue` (D10): "Connect with Shopify" first and the credentials form second, "Reconnect with Shopify", "Update permissions", the removed state, agents without buttons; verify by component tests for each state
- [ ] 5.3 Read `?inclamo_shopify=` in `OrdersSection.vue`, show the one-line result and drop it from the address (D9); verify by component tests for connected, declined and refused
- [ ] 5.4 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 6. End to end

- [ ] 6.1 Extend `e2e/proxy/server.mjs` with the stand-ins of D11 (authorization redirect signed with the e2e app's secret, token answers for a code and for a refresh, rules for a decline, a refused refresh, write-only scopes and a short expiry); verify by a smoke run of the proxy against the e2e app on the test store
- [ ] 6.2 Give the e2e account an operator app in `e2e/setup.rb` through the rake task, and pass the e2e app's secret to the proxy; verify that the setup runs twice without change
- [ ] 6.3 Write `e2e/tests/shopify-oauth-connection.spec.mjs` with one test per scenario named after it, and add "Installation without encryption keys" to `ELSEWHERE` in `scripts/check-e2e-coverage.mjs`; verify the coverage check passes, and the file passes on the stand (holding `~/locks/stand`) and in CI (holding `~/locks/ci-e2e`)
- [ ] 6.4 Run the existing `shopify-connection.spec.mjs` and the order panel files unchanged; verify they pass, so the credentials path is unbroken

## 7. Real Shopify and documents

- [ ] 7.1 Write `docs/operator-shopify-app.md`: the app in the Dev Dashboard (not embedded, App URL, redirection URL, scopes, `app/uninstalled`, `app/scopes_update`, the compliance topics), custom distribution for the merchant's store, the install link, the rake task; verify by following it to create the app for a development store
- [ ] 7.2 Run the flows through Shopify's real consent screen on a development store: connect from the dashboard, install from the link, update permissions, uninstall; add the screenshots to the operator guide; verify each outcome matches its scenario
- [ ] 7.3 From the recorded run, confirm the webhook header names (topic, shop, HMAC, delivery ID) and whether the install link reaches the App URL before or after Shopify's own consent; record both in design D7 and D3; verify by a spec fixture copied from a recorded delivery with secrets removed
- [ ] 7.4 Rewrite `docs/connect-shopify.md` with the button first and the credentials path second; verify every step against the recorded run
