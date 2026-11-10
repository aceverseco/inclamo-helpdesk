## 1. Store side

- [x] 1.1 Probe on the test store with `write_order_edits`: begin, set quantity with restock, add variant, commit with and without notification, invoice send, and the refusal without the scope; verify by a throwaway script whose findings are written into the design
- [x] 1.2 Add the documents and extend the order document with unshipped quantities per line; verify `scripts/check-graphql.mjs` passes and fixtures are recorded without personal data
- [x] 1.3 Make the seed create a product with tracked stock and an order with one shipped and one unshipped item; verify the seed is removed after a run

## 2. Backend

- [x] 2.1 Add the summary call (session, staged changes, calculated totals, nothing committed); verify by a spec that the order is unchanged after a summary
- [x] 2.2 Add the edit action in the runner: staging, commit, notification, invoice for the balance; verify by specs for reduce, remove, add, each option, missing role, missing scope
- [x] 2.3 Refuse to commit when the fresh calculation differs from the summary the agent saw; verify by a spec with a changed order
- [x] 2.4 Return the amount due back and report `can.edit_items`; verify by request specs
- [x] 2.5 Write the record and the private note listing each change; verify by a spec

## 3. Dashboard

- [x] 3.1 Build the edit dialog: lines with quantity controls, locked shipped lines, product search, summary, options; verify by component tests for each state
- [x] 3.2 Show the button only for an editable order, with the role and the scope; verify by component tests for each combination
- [x] 3.3 Open the refund dialog with the amount due back after a save; verify by a component test
- [x] 3.4 Show the store's refusal; add the strings; verify by a component test and `scripts/check-ui-strings.mjs`
- [x] 3.5 Show the current quantities and total in the order card, without the items taken off (founder, 2026-11-07); keep the cards when the panel reads the orders again; verify by component tests and a presenter spec

## 4. End to end

- [x] 4.1 Add `order-item-editing` to the coverage check's capability map with `e2e/tests/order-item-editing.spec.mjs`; verify the check lists its fourteen scenarios
- [x] 4.2 Write the fourteen tests named after the scenarios, checking lines, stock and the sent invoice through the Admin API ("store refuses" with the proxy); verify they pass on the stand
- [x] 4.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain
- [x] 4.4 Add `write_order_edits` to `docs/connect-shopify.md` and describe the action; verify the scope list matches the guide app
