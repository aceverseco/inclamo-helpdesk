## 1. Store side

- [x] 1.1 Probe on the test store with `write_discounts`: create a percentage and an amount code, limited to a customer and open, with an expiry, and the refusal for a duplicate text and without the scope; verify by a throwaway script whose findings are written into the design
- [x] 1.2 Add the discount documents (create, find by code) and the online-store link and publication state to the product search document; verify `scripts/check-graphql.mjs` passes and fixtures are recorded without personal data
- [x] 1.3 Make the seed create one published and one unpublished product and remove every code whose title starts with the run; confirm the store's prefix search on titles; verify nothing is left in the store after a run

## 2. Backend

- [x] 2.1 Return the link and "not in the online store" from the product search; verify by request specs
- [x] 2.2 Add the presets table, model and administrator endpoints with the limits of D4; verify by model and request specs for each limit, an agent refused, and an agent with the right listing
- [x] 2.3 Add the right to give discounts (table, `DiscountGrant.allows?`, give and take endpoints); verify by specs that it is independent of the order-actions role and that administrators always hold it
- [x] 2.4 Add the discount action on the order-less path with the generated text and its retry on `TAKEN`, and the gate on the right; verify by specs for percentage, amount, each expiry, several uses, each audience with and without a matched customer, unknown preset, missing right, missing scope, a taken text and a lost answer
- [x] 2.5 Write the private note only on success and keep a refused attempt in the record without a note; verify by specs for both
- [x] 2.6 Report `write_discounts` in the actions report, `can_give_discounts` and the presets in the panel's answer; verify by request specs

## 3. Dashboard

- [x] 3.1 Add "Insert product" with the shared search and `insertIntoReply` for rich and plain-text channels; verify by component tests for a link, no link and nothing found
- [x] 3.2 Add the settings page "Discount codes": presets with add, edit and delete, and the switches "May give discounts"; verify by component tests for each limit and each switch
- [x] 3.3 Add the "Discount code" dialog: presets with their conditions, "this customer" presets disabled without a matched customer, create and insert, the store's refusal; verify by component tests for each case
- [x] 3.4 Show the controls by right, scope and presets, also without a matched customer, with the lines for a missing permission and for no presets; verify by component tests for each combination
- [x] 3.5 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 4. End to end

- [x] 4.1 Add `reply-inserts` to the coverage check's capability map with `e2e/tests/reply-inserts.spec.mjs`; verify the check lists its eighteen scenarios
- [x] 4.2 Write the eighteen tests named after the scenarios, checking each created code through the Admin API; verify they pass on the stand
- [x] 4.3 Run the full suite in CI on an `e2e/**` branch under the `ci-e2e` lock; verify all tests pass and the log holds no token-shaped string and no store domain
- [ ] 4.4 Add the `write_discounts` row to `docs/connect-shopify.md` and describe the settings page and both controls; verify the scope list matches the guide app
