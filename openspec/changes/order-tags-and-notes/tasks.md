## 1. Store side

- [x] 1.1 Release a version of the test apps with `write_customers`, `write_order_edits` and `write_discounts` (the three scopes the coming changes need) and approve it on the test store; verify with `e2e/check-apps.mjs` that the guide app reports them and the limited app does not
- [x] 1.2 Add the documents for tags add, tags remove, order note and customer note, and read tags and notes in the order and customer documents; verify `scripts/check-graphql.mjs` passes and fixtures are re-recorded without personal data
- [ ] 1.3 Probe on the test store that each mutation works with the scope the design names and is refused without it; verify by a throwaway script whose output is written into the design

## 2. Backend

- [x] 2.1 Add the tag and note actions for orders to the runner; verify by specs for add, remove, note, missing role and missing `write_orders`
- [x] 2.2 Add the same for customers behind `write_customers`; verify by specs including the missing-scope case and the limited mode
- [x] 2.3 Write the record and the private note without the note's text; verify by a spec that the text of a store note never appears in a private note or in `inclamo_order_actions`
- [x] 2.4 Report `write_customers` in the connection's scopes and in the panel's `can` map; verify by request specs

## 3. Dashboard

- [x] 3.1 Show tags and note on the order card and in the customer block; verify by component tests including the limited mode
- [x] 3.2 Add the tag input, the remove control and the note editor, shown only with the role and the scope; verify by component tests for each combination
- [x] 3.3 Show the store's refusal and keep the old value; verify by a component test
- [x] 3.4 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 4. End to end

- [x] 4.1 Add `order-tags-and-notes` to the coverage check's capability map with `e2e/tests/order-tags-and-notes.spec.mjs`; seed an order and a customer with tags and notes; verify the seed is removed after the run
- [x] 4.2 Write the twelve tests named after the scenarios ("store refuses" with the proxy, "without the customer permission" with an app that lacks it); verify they pass on the stand
  - No test app sees customers' data without `write_customers` (the limited app hides customers altogether), so the proxy takes `write_customers` out of the store's scope answer for that test. Passed 12/12 on the stand (run tn…marks, 2026-11-06); the run's seed was removed (0 orders, 0 customers left).
- [x] 4.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain
  - The first run (acb8ecf) failed one connection test that still expected only the four older actions in the report; 29bbd7a fixed both such expectations. Run 42355935766 on 29bbd7a passed 65/65 (2026-11-07); its log holds no token-shaped string and no store domain.
- [x] 4.4 Add `write_customers` to `docs/connect-shopify.md` with what it is used for; verify the scope list there matches the guide app
