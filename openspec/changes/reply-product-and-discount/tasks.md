## 1. Store side

- [ ] 1.1 Probe on the test store with `write_discounts`: create a percentage and an amount code, limited to a customer and open, with an expiry, and the refusal for a duplicate text and without the scope; verify by a throwaway script whose findings are written into the design
- [ ] 1.2 Add the discount document and the online-store link and publication state to the product search document; verify `scripts/check-graphql.mjs` passes and fixtures are recorded without personal data
- [ ] 1.3 Make the seed create one published and one unpublished product and remove every code titled by the run; verify nothing is left in the store after a run

## 2. Backend

- [ ] 2.1 Return the link and "not in the online store" from the product search; verify by request specs
- [ ] 2.2 Add the discount action in the runner with the proposed code text; verify by specs for percentage, amount, each expiry, matched and unmatched customer, missing role, missing scope and a duplicate text
- [ ] 2.3 Write the record and the private note only on success; verify by a spec that a refused code leaves neither
- [ ] 2.4 Report `write_discounts` in the connection's scopes and `can.discount_code` in the panel's answer; verify by request specs

## 3. Dashboard

- [ ] 3.1 Add "Insert product" with the shared search and the insert into the reply for rich and plain-text channels; verify by component tests for a link, no link and nothing found
- [ ] 3.2 Add the "Discount code" dialog and the insert of the created code; verify by component tests for each option and the store's refusal
- [ ] 3.3 Show the controls by role and scope, also without a matched customer; verify by component tests for each combination
- [ ] 3.4 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 4. End to end

- [ ] 4.1 Add `reply-inserts` to the coverage check's capability map with `e2e/tests/reply-inserts.spec.mjs`; verify the check lists its eleven scenarios
- [ ] 4.2 Write the eleven tests named after the scenarios, checking each created code through the Admin API; verify they pass on the stand
- [ ] 4.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain
- [ ] 4.4 Add `write_discounts` to `docs/connect-shopify.md` and describe both controls; verify the scope list matches the guide app
