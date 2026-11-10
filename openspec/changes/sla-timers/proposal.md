## Why

A merchant promises "we answer within two hours" and has no way to see which conversations are about to break that promise. Three of the five e-commerce helpdesks this project is measured against have response and resolution targets with timers. Chatwoot sells this in its paid edition; by this project's rule such features are written by us, in our code, and the paid edition's code is not used.

## What Changes

- **SLA policies** on a settings page: a name, a first-response target, a resolution target, a switch "count business hours only", and the inboxes the policy covers.
- **A timer on the conversation**: an "SLA" section in the conversation sidebar showing the time left to the first response and to the resolution, and whether each target was met or missed.
- **A missed target is marked**: the conversation gets the label `sla-missed` and a private note, so missed conversations show in the list, in saved views, in rules and in reports by label.
- **A summary** per policy on the settings page: how many conversations were covered and what share met each target.

Not in this change: a target for every next reply, pausing while waiting for the customer, new timers when a resolved conversation is reopened, warnings before a target is missed, policies chosen by rule conditions.

## Capabilities

### New Capabilities
- `sla-timers`: what a policy is, which conversations it covers, how the two timers run and stop, how business hours count, what marks a missed target and what the summary shows.

### Modified Capabilities
- none.

## Assumptions to confirm

1. Two targets: first response and resolution. No target for each next reply.
2. A policy covers inboxes (all or chosen); the first policy in the list that covers the inbox wins.
3. Only a public reply by a person meets the first-response target; automatic messages do not.
4. A missed target is shown by a label and a private note; nobody is emailed or notified.

## Impact

- Backend: two tables of our own (policies, applied timers), a periodic check for missed targets, endpoints for policies, the timer and the summary. Chatwoot's own SLA tables, flags and screens are not used.
- Dashboard: a section in the sidebar registry and a page in the settings registry; no new seam.
- No Shopify scope: this change does not touch the store.
- Tests: backend specs with time travel, component tests, end-to-end tests for every scenario.
