## 1. Contract

- [ ] 1.1 Write `docs/ai-connector.md` from design D2–D8: the connection code; the registration and removal calls; the events consumed and the fields read (message, conversation, attachment), with which to ignore (the bot's own messages, private notes, conversations not Pending); the signature check, timestamp window and de-duplication by `X-Chatwoot-Delivery`; answering `200` within 5 s and working after; retries (429 and 500 only) and what any other failure does; the Chatwoot calls with a bot token (reply, private note, typing, hand over, resolve, priority, team assignment, custom attributes) and our two endpoints; the labels and when each is used; the rate limit; acting only on conversations of connected inboxes; handing over with `inclamo_error` after a failure of its own. Verify each requirement of the spec maps to a section and each call names its Chatwoot source line
- [ ] 1.2 Agree the registration call's shape (D3, step 3) with the builder of the AI service and record the outcome in design D3; verify the document and the design say the same

## 2. Backend: the connection

- [ ] 2.1 Pick a migration version after checking the other branches' `custom/db/migrate`; add `inclamo_ai_connections` and `Inclamo::AiConnection` (one per account, states, refusal without encryption keys); verify by model specs
- [ ] 2.2 Decode connection codes (format, HTTPS unless private network is allowed); verify by specs for a valid code, text that is not a code, an HTTP address and a missing field
- [ ] 2.3 Write the registration client over SafeFetch with a 10 s limit; verify by specs on recorded answers: `201`, a `4xx` with a message, a `5xx`, a timeout
- [ ] 2.4 Write the connect service in the order of D3; verify by specs that a refusal leaves no bot, no new "Phone" inbox and no labels, and that a success attaches only the chosen inboxes, sets the bot's address, turns `keep_pending_on_bot_failure` off and creates the labels of D7 without touching existing ones
- [ ] 2.5 Refuse inboxes that have another bot or Dialogflow; verify by a spec
- [ ] 2.6 Write the disconnect service of D4; verify by specs that pending conversations are opened, the token is refused at once, the bot is removed, "Phone" and labels stay, and an unreachable AI service is noted without stopping the disconnection
- [ ] 2.7 Add `GET/POST/DELETE inclamo/ai/connection` for administrators; verify by request specs, an agent refused

## 3. Backend: what the agent uses

- [ ] 3.1 Authenticate our agent endpoints by the connected bot's token and the conversation's inbox; verify by request specs: another inbox, another bot's token, a user's token, a disconnected account
- [ ] 3.2 Add the messages endpoint of D6; verify by request specs on a conversation made through the widget with text, one image, an image without text and a private note: roles, order, files, `shopper_files`, the note absent, the limit
- [ ] 3.3 Add the labels endpoint of D6; verify by specs that the team's labels stay, a missing `inclamo_` label is created with the description, other names are refused
- [ ] 3.4 Add the listener of D5; verify by specs that a user's public reply and a user's assignment open a pending conversation of a connected inbox, and that a private note, a bot reply and a conversation of another inbox do not
- [ ] 3.5 Prepend the delivery recorder of D8 and the reply listener; verify by specs for a `200`, a `503`, a refused connection, a webhook of another kind that is not recorded, and a spec that fails when the prepended method no longer exists
- [ ] 3.6 Confirm on the stand the facts the design takes from the source: the payload of a widget message with one image, the events after `bot_handoff!`, a pending conversation opened after a `503`; verify by recording one of each in `docs/ai-connector.md` with secrets and personal data removed

## 4. Dashboard

- [ ] 4.1 Build `AiAgentPage.vue` (not connected, connected, failing; the inbox picker; disconnect with confirmation) and register it in `settingsPages.js` for administrators; verify by component tests for each state
- [ ] 4.2 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 5. Stand-in agent and end to end

- [ ] 5.1 Build `e2e/stand-in-agent/` (D10) and add it to the e2e stack with `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` for that stack only; verify by its own tests that a wrong signature, an old timestamp and a repeated delivery are refused
- [ ] 5.2 Add `ai-agent-connection` to the coverage check's map with `e2e/tests/ai-agent-connection.spec.mjs`; verify `scripts/check-e2e-coverage.mjs` lists every scenario
- [ ] 5.3 Write the tests named after the scenarios: shopper in the widget with image fixtures, team in the dashboard, agent as the stand-in; verify they pass on the stand and assert no wording of the agent
- [ ] 5.4 Run the full suite in CI on an `e2e/**` branch; verify all tests pass and the log holds no token-shaped string
- [ ] 5.5 Describe in `docs/ai-connector.md` how the same file runs against the AI service with a code it issued; verify the document names the variables and the test file reads them
