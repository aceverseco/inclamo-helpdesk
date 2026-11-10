## 1. Groundwork

- [x] 1.1 Make `scripts/check-e2e-coverage.mjs` count a change only once its `tasks.md` has a ticked task, and print the changes it skipped; verify the check passes with the seven untouched changes present and fails when a started change lacks a test
- [x] 1.2 Add `reply-order-variables` to the coverage check's capability map with a new test file `e2e/tests/reply-order-variables.spec.mjs`; verify the check lists its nine scenarios as missing

## 2. Server side

- [x] 2.1 Read how the dashboard resolves and warns about variables (`VariableList.vue`, `editorHelper.js`, the reply box) and write the findings into design D3; verify the planned patch touches at most two core files
- [x] 2.2 Add the `order` drop and prepend it into the message drops; verify by specs on recorded answers that every variable of the spec renders for a tied order, including items and total
- [x] 2.3 Add the 3-second limit and the fallback to conversation attributes; verify by specs for a timeout and for an authentication error that the message is created with the last known values
- [x] 2.4 Verify by a spec that a message without order variables makes no store call, and that a conversation without a tied order renders the variables as empty text
- [x] 2.5 Move the status words into one table shared by the panel's presenter and the drop; verify by a spec that both give the same words for every status in the fixtures

## 3. Dashboard

- [x] 3.1 Write `patches/0003-reply-variables.patch` and the registry file; verify `scripts/assemble.sh` applies all three patches on a clean v4.19.1 tree and Chatwoot's own tests around the patched files pass
- [x] 3.2 Register the order variables with descriptions and values from the panel's store; verify by component tests that the list shows them with a connection and hides them without one
- [x] 3.3 Verify by a component test that a reply with `{{order.number}}` and no tied order triggers the editor's undefined-variable warning
- [x] 3.4 Add the strings to our locale file; verify `scripts/check-ui-strings.mjs` passes

## 4. End to end

- [x] 4.1 Write the nine tests named after the scenarios, using the seeded store and the proxy for "store unreachable"; verify they pass on the stand after an image rebuild
- [x] 4.2 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string and no store domain
- [x] 4.3 Add a section on order variables to `docs/`; verify every variable of the spec is listed there

## 5. The latest order when none is tied (decided 2026-11-07)

- [x] 5.1 Make the drop fall back to the first order of the matched customer's list when no order is tied, within the one 3-second budget; verify by specs on recorded answers that the tied order wins, that the latest order serves when none is tied, that a contact without a customer renders empty text, and that a store that does not answer leaves every variable of an untied conversation empty
- [x] 5.2 Put `variables` on every order of the panel's list and make the dashboard's entry fall back to the first of them; verify by component tests that the editor resolves and the list previews the latest order when none is tied, and that the warning comes only when the panel found neither
- [x] 5.3 Add the two new end-to-end tests and rename the two whose scenarios changed; verify they pass on the stand and the full suite passes in CI on an `e2e/**` branch with a clean log
- [x] 5.4 Update `docs/order-variables.md` ("Which order"); verify it names the default, the tie that overrides it and the case with neither
