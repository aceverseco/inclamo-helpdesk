## 1. Store side

- [x] 1.1 Probe on the test store: draft create, calculate, invoice send and the list of open drafts by customer and tag with the scopes the guide app holds; verify by a throwaway script whose findings are written into the design
- [x] 1.2 Probe on the stand that the editor-insert event puts text into the reply box from a sidebar component, in the widget inbox and in an email inbox; verify by hand and write the result into design D3
- [x] 1.3 Add the documents (calculate, create, invoice send, open drafts, product search); verify `scripts/check-graphql.mjs` passes and fixtures are recorded without personal data

## 2. Backend

- [x] 2.1 Add the product search endpoint (title or SKU, variants with price and availability); verify by request specs including the missing `read_products` case
- [x] 2.2 Add the preview (calculation only, nothing created); verify by a spec that no draft exists after a preview
- [x] 2.3 Add the new-order action in the runner with discount, shipping charge, note and "order again" prefill; verify by specs for each option, missing role, missing scope, limited mode and the store's refusal
- [x] 2.4 Add the two deliveries and the "no email" rule; verify by specs that the invoice is sent only when chosen and only with an email
- [x] 2.5 Add the list of orders awaiting payment to the panel's answer; verify by specs that a paid draft leaves the list and the cache is dropped after the action
- [x] 2.6 Write the record and the private note; verify by a spec that they hold the total and the delivery and no address

## 3. Dashboard

- [x] 3.1 Build the product search component; verify by component tests for results, no results and an unavailable variant
- [x] 3.2 Build the new-order dialog (lines, discount, shipping, note, summary, delivery choice); verify by component tests for each step and the store's refusal
- [x] 3.3 Add "order again" on the order card and the block of orders awaiting payment; verify by component tests
- [x] 3.4 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 4. End to end

- [x] 4.1 Add `order-creation` to the coverage check's capability map with `e2e/tests/order-creation.spec.mjs`; make the seed remove every draft tagged by the run; verify nothing is left in the store after the run
- [x] 4.2 Write the eleven tests named after the scenarios, checking the store through the Admin API for the draft, its lines and the sent invoice; verify they pass on the stand
- [x] 4.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain
- [x] 4.4 Describe the action in `docs/`; verify the scopes named there match the spec
