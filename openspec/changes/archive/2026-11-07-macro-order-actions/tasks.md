## 1. Backend

- [x] 1.1 Extend the macro's allowed steps with the four names; verify by model specs that a macro with them saves and an automation rule with them is rejected
- [x] 1.2 Implement the four steps over the runner with the fixed options of the spec; verify by specs on recorded answers for each step
- [x] 1.3 Stop the loop after a failed order step and write the private note; verify by specs for no tied order, no role, missing scope and the store's refusal that later steps did not run and earlier ones did
- [x] 1.4 Store the macro's id on the action row; verify by a spec
- [x] 1.5 Add the preview endpoint; verify by request specs that its amounts equal what the step then refunds, and that it answers "no order" without calling the store

## 2. Dashboard

- [x] 2.1 Write `patches/0004-macro-steps.patch` and the registry file; verify `scripts/assemble.sh` applies all patches on a clean v4.19.1 tree and Chatwoot's own macro tests pass
- [x] 2.2 Register the four steps with their descriptions, only with a working connection; verify by component tests
- [x] 2.3 Build the confirmation dialog fed by the preview, with the "no order" state; verify by component tests for confirm, decline and no order
- [x] 2.4 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 3. End to end

- [x] 3.1 Add `macro-order-actions` to the coverage check's capability map with `e2e/tests/macro-order-actions.spec.mjs`; seed orders for refund, shipping refund, cancel and replacement; verify the seed and the replacement orders are removed after the run
- [x] 3.2 Write the eleven tests named after the scenarios, checking refunds, cancellation and the new order through the Admin API; verify they pass on the stand
- [x] 3.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain
- [x] 3.4 Describe the steps and their fixed behaviour in `docs/`; verify each step of the spec is listed
