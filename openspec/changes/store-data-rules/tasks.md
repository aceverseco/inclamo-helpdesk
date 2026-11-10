## 1. Facts

- [x] 1.1 Confirm on the stand that an automation rule with a number-type custom attribute and "greater than" fires as expected; verify by a rule created through the API and one conversation above and one below the value
- [x] 1.2 Extend the customer search document with tags and the latest order's statuses, total and tags; verify `scripts/check-graphql.mjs` passes and the fixtures are re-recorded without personal data
- [x] 1.3 Add the eight attribute definitions and the writer of facts; verify by specs for a matched customer, an unmatched contact and the limited mode
- [x] 1.4 Refresh the facts on every panel read of the customer; verify by a spec that nothing is written when nothing changed
- [x] 1.5 Narrow the order panel's spec "a read writes nothing to the database" to the modified requirement: a read writes nothing but the conversation's attributes and their definitions; verify the panel's request specs pass

## 2. Order of work

- [x] 2.1 Prepend the automation listener so enrichment and the auto-tie run before the rules of a new conversation; verify by a spec that a rule on total spent fires on the first message
- [x] 2.2 Add the 5-second limit; verify by specs for a timeout and a refused token that the rules still run and the conversation exists
- [x] 2.3 Verify by a spec that the attribute write starts no second evaluation of rules
- [x] 2.4 Verify by a spec that a rule's message with `{{order.number}}` is rendered when the first message names the customer's order

## 3. Presets

- [x] 3.1 Add the presets endpoint (list, switch on with a value, switch off), administrators only; verify by request specs including the agent-forbidden case
- [x] 3.2 Create the rule with its marker and the labels it needs; verify by specs that switching off keeps an edited rule's conditions
- [x] 3.3 Add the presets page to the settings registry with its strings; verify by component tests for on, off, the value field and the failed state
- [x] 3.4 Write `patches/0005-rule-operators.patch` and the registry file so the rule editor offers "greater than", "less than" and "contains" for the store's attributes (design D11); verify the patch applies on v4.19.1, a component test pins the operators and Chatwoot's own test of the helper passes

## 4. End to end

- [x] 4.1 Add `store-data-rules` to the coverage check's capability map with `e2e/tests/store-data-rules.spec.mjs`; seed a customer above and below the amount, a tagged customer and an unknown contact; verify the seed is removed after the run
- [x] 4.2 Write the eleven tests named after the scenarios (the limited-mode one with the store's refusal of customer data answered by the proxy, as the order panel's test does: the app without a distribution method cannot be connected at all; "store silent" with the proxy); verify they pass on the stand
- [x] 4.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain (73 of 73, run 42238158519)
- [x] 4.4 Describe the conditions and the presets in `docs/`; verify every condition of the spec is listed
