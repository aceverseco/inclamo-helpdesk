## 1. Backend

- [ ] 1.1 Create the `inclamo_call_conversations` table and model, unique on account and call id (D3), with a migration version no other change uses (check every worktree's `custom/db/migrate` and the stand's spec sources first); verify by model specs for uniqueness per account and the same call id in two accounts
- [ ] 1.2 Add the calls route and controller under the overlay's routes, skipping Chatwoot's bot endpoint list and admitting only the connection's agent bot (D2); verify by request specs for no token, an administrator's token, another bot's token, the connection's bot, no connection and a switched-off connection
- [ ] 1.3 Validate the filing and answer the refusal codes (D8); verify by request specs for each field rule, `invalid_call`, `invalid_label`, `too_large`, and that no refusal body or log line holds a turn, a number or an email
- [ ] 1.4 Implement the contact rule (D4); verify by specs for one contact by number, one by email, two by number, two by email, no number and no email, a new named caller, a storefront caller without a name, and that a found contact's name, email and phone are unchanged
- [ ] 1.5 Write the conversation in one transaction: contact inbox of the Phone inbox, conversation with status, priority and the `inclamo_call_*` attributes, the turns as message rows with their times, the record as a private note last, the labels, the key row (D5, D6); verify by specs that the messages come back in call order through Chatwoot's own messages endpoint with the right sender and type, that the note is last and private, and that a failure at any step leaves nothing behind
- [ ] 1.6 Add labels the account does not list yet to its labels on first use; verify by a spec that `labels_added` names them and a second call adds none
- [ ] 1.7 Implement the repeat and the concurrent repeat (D3); verify by a spec that a second filing answers 200 with `found: true` and changes no row, and by a spec that forces the unique-index conflict and still yields one conversation
- [ ] 1.8 Mask card numbers before storing (D7); verify by specs for spaced, dashed and plain card numbers in a turn, the record and the name, and for a long number that fails the Luhn check staying as sent
- [ ] 1.9 Verify filing reaches nobody: specs that filing a call enqueues no send job, gives the agent bot no event, gives the assignee no new-message notification for the turns, and does not reopen or re-status the conversation after the transaction
- [ ] 1.10 Read which time the dashboard shows for a message (`created_at` or `external_created_at`) and set the turn time where it shows; verify by a spec on the messages endpoint and a note in design D5 with the file and line read
- [ ] 1.11 Define the eight `inclamo_call_*` conversation attributes (D6) as one more step of connecting the AI agent (`ai-agent-connection`), keeping a definition the merchant already has under the same key; verify by a spec that connecting defines all eight once, a second connection changes nothing, and a disconnection keeps them

## 2. Dashboard

- [ ] 2.1 Build the call card reading the conversation's `inclamo_call_*` attributes, with words for entry, outcome and how the contact was found, the duration as minutes and seconds, and the recording link opening in a new tab; verify by component tests for a full card, a card without recording, without a caller number and with an outcome the card does not know
- [ ] 2.2 Register the card in seam 1 with `visible` true only for conversations that have `inclamo_call_outcome`; if `sla-timers` is not merged, carry its `visible` hook in patch 0001 unchanged; verify `scripts/assemble.sh` applies all patches on a clean v4.19.1 tree and Chatwoot's own sidebar tests pass
- [ ] 2.3 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 3. Contract

- [ ] 3.1 Bring `docs/ai-connector-calls.md` in line with the code (request, answer, codes, contact rule, limits, what the helpdesk never does) and link it from `docs/ai-connector.md`; verify every requirement of the spec has its line in the document and the document holds no client name or data

## 4. End to end

- [ ] 4.1 Add the call fixtures (invented: numbers 555-01xx, addresses at `example.com`) and the filing step to the stand-in agent of `ai-agent-connection`; verify it files a fixture on the stand and lists the agent bot events it received
- [ ] 4.2 Add `call-conversations` to the coverage check's capability map with `e2e/tests/call-conversations.spec.mjs`; verify `scripts/check-e2e-coverage.mjs` fails until every scenario has a test
- [ ] 4.3 Write the tests named after the scenarios, reading the dashboard for the conversation, its messages, note, labels, status, priority and card, the contact's page for "the caller chatted before", the stand-in's event list for "the agent bot stays quiet", the assignee's notifications for "no notification for each turn", and the mail catcher of the stand for "the agent's turns stay records" (a backend spec stands in when the stand has none); verify they pass on the stand under the stand lock
- [ ] 4.4 Run the full suite in CI on an `e2e/**` branch under the CI lock; verify all tests pass and the log holds no token-shaped string and no number outside the fixtures' 555-01xx
