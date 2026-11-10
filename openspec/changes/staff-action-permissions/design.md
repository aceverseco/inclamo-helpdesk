## Context
See proposal.md. OrderRole currently means all non-discount actions; DiscountGrant is separate. All mutations already pass through OrderActionRunner, including macro steps.

## Goals / Non-Goals
Goals: one server authorization contract and no accidental loss/escalation of existing grants. Non-goals: replacing Chatwoot roles or its paid custom-role feature.

## Decisions
- Add an action list to OrderRole, migrating existing rows to the explicit non-discount action set. Keep DiscountGrant as the storage for discount permission to preserve existing clients/settings. A common permission facade serves both.
- The existing administrator-only bulk grant/revoke endpoints remain compatible. A new update operation changes one known action under a membership row lock, preventing lost updates. Responses add a permissions map while preserving aggregate fields.
- Pass action and parameters to the common runner gate, including refund-on-cancel and discount-on-new-order. Preview and retry use the same gate. An item edit records an amount due back; refund stays a separate action.
- Reuse a standalone permission editor inside the settings page and onboarding. Each member has an accessible action grid; no horizontal table is required on a laptop. Existing settings route stays valid.

## Risks / Trade-offs
- [Old clients assume a broad role] → preserve bulk API and aggregate fields; current controls use the per-action map.
- [Rights changed after rendering] → always check server-side, including macros and recovery POSTs.
- [Concurrent administration] → serialize updates by account membership.
- [Discounts inside new orders were formerly included] → explicitly require discount authority; do not grant discount-code access during migration.

## Migration Plan
Add the permission column and backfill only existing order-role rows. Rollback to the old binary would broaden granular grants, so rollback requires restoring the pre-migration database or retaining the new authorization code. Deploy only after the new UI and API pass together in an isolated stack.
