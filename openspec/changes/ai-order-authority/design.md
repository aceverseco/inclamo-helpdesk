## Context
See proposal.md. AiConversationsController already validates the active bot and connected inbox. OrderActionRunner owns mutation/recovery records. The AI service remains separate; local tests use its deterministic contract simulator.

## Goals / Non-Goals
Goals: fail closed at a single execution boundary and retain readable review/audit evidence. Non-goals: implementing the model service, spending on a new AI provider or calling real customers.

## Decisions
- Store per-account action policies with propose defaults, mode, allowed fulfillment states, shop currency and monetary limits. For order actions the maximum is the current order total; refund amount is additionally bounded. New-order and edit previews also bound the calculated resulting total; discount presets have fixed-amount/percentage limits. UI explains these meanings and that these are per-action limits.
- Store proposals separately from mutation records. Canonical request digest prevents reusing an identifier for changed input. Sensitive parameters (addresses/notes) are encrypted; responses expose them only within authorized conversation context. Proposals expire after 15 minutes and can be refreshed for review without mutating Shopify.
- Read a fresh order/customer and calculate a server summary. Bind approval to a summary digest and the current shop connection identity; reject stale confirmations. Keep the existing runner's mutation idempotency and unknown-outcome recovery.
- Bot context comes from authenticated server state. No fake administrator/account member is created. The runner accepts a narrow internal authorizer and actor metadata supplied only by the proposal executor, not request parameters. Staff approvals use real membership grants.
- Require a pending conversation and the same active bot for autonomous execution. A verified widget identity or an explicit staff verification bound to the matched customer enables autonomous changes; a bare unverified contact email is insufficient. Staff can review proposals without granting ongoing autonomous identity trust.
- Serialize proposal execution with a PostgreSQL session advisory lock, then attach the underlying action result. Do not wrap remote writes in a database transaction: the runner journal must commit before Shopify receives a mutation. Recheck policy, bot and staff authority at the runner boundary. Audit names the initiator and approver. UI provides review, refresh, approve and reject controls in the conversation.

## Risks / Trade-offs
- [A delayed request races with takeover/revocation] → recheck active bot, conversation, policy and rights at the runner gate immediately before the write; proposal duplicates are serialized by an account advisory lock. A remote write and local takeover cannot form a distributed transaction.
- [Shopify changes between read and write] → fresh reads, handler preconditions and edit expected totals; Shopify has no universal transaction spanning our database.
- [Unknown outcome] → retain the same action id and existing read-only recovery; never automatically create another mutation attempt.
- [Unverified widget contact] → require verified identity for autonomy and expose human review as the available path.

## Migration Plan
Add policy/proposal/audit metadata tables/columns without changing an existing bot's effective ability to mutate. Defaults only propose. Exercise policies and proposals on an isolated development store before any deployment.
