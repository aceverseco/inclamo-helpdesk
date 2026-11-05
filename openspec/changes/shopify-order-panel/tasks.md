## 1. Overlay foundation and image

- [x] 1.1 Create the `custom/` skeleton (`app`, `lib`, `config/routes.rb`, `db/migrate`) and the initializer that adds its load paths, draws its routes and appends its migration path (D1); verify on a stock Chatwoot v4.19.1 checkout that `ChatwootApp.custom?` is true, a probe route under `/api/v1/accounts/:account_id/inclamo/` answers, and `db:migrate` runs a probe migration from `custom/db/migrate`
- [x] 1.2 Add the image build (assemble script plus Chatwoot's own Dockerfile) from the pinned official CE tag plus `custom/` plus the seam patches (D11); verify the image boots with the stock compose file and the probe route answers
- [x] 1.3 Add the CI job that builds the image and fails when a seam patch does not apply; verify by a deliberately broken patch on a branch
- [x] 1.4 Add the backend test harness that runs our specs inside the Chatwoot test environment at the pinned tag; verify one passing spec in CI

## 2. Shopify client

- [x] 2.1 Implement the Admin GraphQL client with the API version in one constant (`2026-10`), time limit and throttle handling that honours the wait Shopify states (D5); verify with specs on recorded answers for success, throttled-then-success and timeout
- [x] 2.2 Add the schema check that validates every GraphQL document of this change against the published schema of the pinned version (D12); verify CI fails on a document with an unknown field
- [x] 2.3 Record the fixture set used by the specs below (shop, scopes, customers, orders, refunds, draft orders, error answers); verify fixtures contain no real personal data by a grep in CI

## 3. Store connection

- [x] 3.1 Create the `inclamo_shopify_connections` table and model with encrypted secret and token, one row per account (D3); verify by model specs for uniqueness, encryption at rest and refusal when encryption keys are absent
- [x] 3.2 Implement `StoreConnection` for the `client_credentials` kind: token exchange, expiry, renewal five minutes before expiry; verify by specs with time travel that an expired token is renewed without an error reaching the caller
- [x] 3.3 Implement the `legacy_token` kind behind the same interface; verify the same read specs pass with both kinds
- [x] 3.4 Implement verification on connect and on "check again": shop, granted scopes, customer-data probe giving `full` or `limited` (D4); verify by specs for valid credentials, app not installed, token refused, bad domain, missing `read_orders`, limited store
- [x] 3.5 Implement the connection endpoints (show, create, recheck, destroy), administrators only, never returning the secret (D2); verify by request specs including the agent-forbidden case and that secrets are absent from responses and logs
- [x] 3.6 Mark the connection as broken on an authentication error from Shopify and report it; verify by a spec that a 401 on an order read flips the status and the next read returns the broken state without calling Shopify
- [x] 3.7 Implement removal: delete credentials, token and scopes, keep the action records; verify by a spec that `inclamo_order_actions` rows survive

## 4. Order-actions role

- [x] 4.1 Create the `inclamo_order_roles` table and the policy "administrator, or agent holding the role" (D13); verify by policy specs for administrator, agent with the role, agent without it, agent of another account
- [x] 4.2 Implement the `order_roles` endpoints (list agents with their state, give, take), administrators only; verify by request specs including the agent-forbidden case and that a newly added agent has no role

## 5. Customer matching and order reads

- [x] 5.1 Implement matching by email, then phone, with the ambiguous and no-match outcomes and the remembered choice stored as a contact attribute (D6); verify by specs for one match by email, two by phone, none, contact without email and phone
- [x] 5.2 Implement the order list (ten per page, newest first, load more) and the single order read with items, statuses, address, shipments, refunds, refundable amount and admin link; verify by specs for an order with two shipments and a partially refunded order
- [x] 5.3 Implement lookup by order number and keeping that customer for the contact; verify by a spec for an existing and a missing number
- [x] 5.4 Implement the limited mode in the reads: order-number lookup only, name and address reported as unavailable; verify by specs on limited-store fixtures
- [x] 5.5 Add the 60-second Redis cache keyed by account and customer, dropped after every action; verify by a spec that a second read within 60 s makes no Shopify call and a read after an action does
- [x] 5.6 Verify by a spec that no order or customer data is written to the database by any read

## 6. Order tied to the conversation

- [x] 6.1 Implement mark, change and clear of the conversation's order and the conversation attributes (number, payment status, fulfilment status, first tracking number and link, admin link), refreshed on every read; verify by request specs and that the shipping address never appears in attributes
- [x] 6.2 Implement automatic marking when the customer's first message contains an order number of the matched customer; verify by specs for own order number, someone else's number and no number
- [x] 6.3 Create the custom attribute definitions on connect so macros and automation rules can pick them; verify they appear in Chatwoot's attribute list for the account

## 7. Order actions

- [x] 7.1 Create the `inclamo_order_actions` table and the action runner: action id from the dialog, record written before Shopify is called, repeated id returns the recorded outcome, outcomes `accepted`, `refused`, `unknown` (D7, D8); verify by specs for repeat, refusal and lost answer
- [x] 7.2 Gate every action on the server by role, then by scope, before any Shopify call; verify by request specs that an agent without the role and a connection without the scope are refused with zero Shopify calls and a `refused` record
- [x] 7.3 Write the private note through Chatwoot's message builder as the acting agent for accepted actions only, without personal data; verify by specs that a refused action writes no note and that the address-change note has no address
- [x] 7.4 Implement cancel with reason, refund, restock and notify, polling up to 10 s and the "cancelling" state; verify by specs for confirmed, still running and refused by the store
- [x] 7.5 Implement refund (full, by line items, shipping, custom amount) with the refundable check before Shopify and the action id as idempotency key; verify by specs for partial amount, amount above the refundable, and repeat after a lost answer giving one refund
- [x] 7.6 Implement the shipping address change for orders without a shipment; verify by specs for an unfulfilled order, a shipped order and the limited mode
- [x] 7.7 Implement the free replacement through a draft order: create from order, update (kept items, full discount, free shipping, tag and note naming the original), complete; draft id recorded after the first step; draft deleted on a later refusal (D14); verify by specs for success, refusal at completion with the draft removed, failed deletion naming the draft, and repeat after a lost answer giving one order

## 8. Dashboard

- [ ] 8.1 Add the sidebar section registry and the two seam patches in `ContactPanel.vue` and `useUISettings.js` (D9); verify the stock sidebar is unchanged with an empty registry and that a registered probe section can be collapsed and reordered
- [ ] 8.2 Build the "Orders" section: not connected, broken, loading, store not answering with retry, limited mode, matched customer with orders, ambiguous match, lookup by order number; verify by component tests for each state
- [ ] 8.3 Build the administrator menu in the section: connect dialog (domain, credentials, scopes to grant), "check again", remove, and the list of agents with the order-actions switch (D10, D13); verify by component tests that an agent never sees the menu
- [ ] 8.4 Build the order card (items, statuses, address, shipments with tracking links, refunds, admin link, mark as the conversation's order); verify by component tests on the fixture orders
- [ ] 8.5 Build the action dialogs (cancel, refund, address, replacement) with confirmation texts, unavailable states naming the reason (no role, missing scope, already shipped), "cancelling" and "outcome unknown"; verify by component tests for each dialog and each unavailable reason
- [ ] 8.6 Add English locale strings for everything above in our own locale file; verify no hard-coded user-facing string remains by a lint rule or grep in CI

## 9. End-to-end tests

- [ ] 9.1 Prepare the dedicated development store and its three custom apps: the helpdesk app with exactly the scopes of the merchant guide, the seeding app with wider scopes, and an app without protected customer data; verify each app's token exchange succeeds and the granted scopes match by a script in `e2e/`
- [ ] 9.2 Add the end-to-end environment: compose with our image, Postgres, Redis, the controllable proxy in front of Shopify, and a seed that creates the account, the administrator and two agents; verify one command brings it up and a smoke test logs in
- [ ] 9.3 Add the store seeding and cleanup helpers (customers, products, orders in the states the scenarios need, tagged per run); verify a run leaves no tagged data in the store
- [ ] 9.4 Write the end-to-end tests of the `shopify-connection` scenarios (connect with client ID and secret, legacy token where the store has one, token renewal, app not installed, token refused, bad domain, agent forbidden, missing read scope, write scopes and "check again", limited mode, secret never shown, second store refused, broken connection, removal); verify all pass against the development store
- [ ] 9.5 Write the end-to-end tests of the panel and matching scenarios (section in the sidebar, not connected, one match by email, two by phone, unknown contact with order number, contact without email and phone, limited mode, two shipments, partial refund, order changed in the store, mark an order, order number in the first message, someone else's order number); verify all pass
- [ ] 9.6 Write the end-to-end tests of the role scenarios (agent without the role, administrator gives the role, role taken away during a confirmation, agent tries to give the role); verify all pass
- [ ] 9.7 Write the end-to-end tests of the action scenarios (cancel with refund and restock, order the store will not cancel, partial refund, amount above the refundable, change address, already shipped, free replacement, item no longer in stock, missing draft orders scope, private note and action record, refused action); verify all pass and the store holds exactly the expected orders and refunds
- [ ] 9.8 Write the end-to-end tests of the failure scenarios through the proxy (store does not answer, throttling, lost answer on refund and on replacement giving one refund and one order, cancellation still running, authentication error); verify all pass
- [ ] 9.9 Add the coverage check that maps every scenario of both specs to an end-to-end test by name, and the CI job that runs the suite on the main branch, before a release and on demand with credentials from CI secrets; verify the check fails when a scenario has no test and that no secret appears in the job log

## 10. Documents and manual checks

- [ ] 10.1 Write the merchant guide: creating the custom app in the Dev Dashboard, the scopes to grant, where to find the client ID and secret, what the limited mode means; verify by following it on the development store from scratch
- [ ] 10.2 Record in the design what the end-to-end runs showed for the items left open: whether a Dev Dashboard custom app can take `read_all_orders`, how completing a zero-total draft behaves and which notification the store sends, and whether an app without protected customer data is possible on a development store
- [ ] 10.3 Check once on a real Basic-plan store what a merchant's own custom app receives and whether the free replacement works there; update the design and the limited-mode scenarios if the result differs
- [ ] 10.4 Open the upstream proposal for the sidebar section registry in the Chatwoot repository and link it from the design
