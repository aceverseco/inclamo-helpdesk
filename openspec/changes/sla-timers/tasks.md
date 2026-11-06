## 1. Data and time

- [x] 1.1 Read in Chatwoot's open code how a message created by an automation rule, a bot or a campaign is told from an agent's reply, and write the markers into design D2; verify with a spec that builds one message of each kind
- [x] 1.2 Create the two tables and models; verify by model specs for the "at least one target" rule, ordering and the copied targets
- [x] 1.3 Implement the elapsed-time function with business hours; verify by specs for plain time, an overnight gap, a weekend, a closed day, an inbox without hours and a daylight-saving change

## 2. Timers

- [x] 2.1 Apply the first covering policy on conversation creation; verify by specs for all inboxes, chosen inboxes, no policy and the order of policies
- [x] 2.2 Stop the first-response timer on the first human public reply and the resolution timer on the first resolution; verify by specs for a private note, a rule's message, a bot's message and an agent's reply
- [x] 2.3 Add the periodic check with its interval setting: mark once, add the label and the private note; verify by specs with time travel that a second run adds nothing
- [x] 2.4 Stop running timers when their policy is deleted and keep applied targets when it is edited; verify by specs

## 3. Endpoints

- [x] 3.1 Add the policy endpoints (list, create, update, reorder, delete), administrators only; verify by request specs including the agent-forbidden case
- [x] 3.2 Add the conversation timer endpoint for agents of the inbox; verify by request specs for running, paused, met and missed states
- [x] 3.3 Add the summary endpoint for 7 and 30 days; verify by a spec for one met, one missed and one running timer

## 4. Dashboard

- [x] 4.1 Add the SLA page to the settings registry: list, form with units, inbox choice, reorder, delete, summary; verify by component tests including the validation message
- [ ] 4.2 Add the "SLA" section to the sidebar registry, shown only when the conversation has a timer, with a local countdown; verify by component tests for each state
- [ ] 4.3 Add the strings; verify `scripts/check-ui-strings.mjs` passes

## 5. End to end

- [ ] 5.1 Add `sla-timers` to the coverage check's capability map with `e2e/tests/sla-timers.spec.mjs`; set the check interval to a few seconds in the test stack; verify the check lists its fourteen scenarios
- [ ] 5.2 Write the fourteen tests named after the scenarios, creating short-target policies through the API for the "missed" ones and an inbox closed now for the business-hours one; verify they pass on the stand
- [ ] 5.3 Run the full suite in CI on an `e2e/**` branch; verify all tests pass
- [ ] 5.4 Describe policies, timers and the label in `docs/`; verify each requirement of the spec has a paragraph
