## Context
See proposal.md. Settings pages already expose connection, staff rights and AI connection controls, but connecting Shopify is initiated from OrdersSection inside a conversation.

## Goals / Non-Goals
Goals: shared state and reliable prerequisite reporting. Non-goals: replacing the separately planned OAuth/sign-in changes or calling a merchant pilot ready from a successful connection check.

## Decisions
- Add an administrator setup route and an account-scoped status record for reviewed steps/completion. Compute connection and channel readiness from current records; never trust booleans supplied by the browser for those checks.
- Reuse ConnectDialog and embeddable staff/AI authority editors. Channel/team steps link to native settings and preserve progress. Changing rights in either location updates the same data.
- Review acknowledgements bind to current permission/policy digests; changed settings invalidate the corresponding review. Completion checks all prerequisites again server-side.
- Show AI as optional for human operation, and provide a clear test checklist plus conversation entry. Display actual recorded order-action evidence separately from generic setup completion; do not create financial test orders merely by loading the wizard.

## Risks / Trade-offs
- [Duplicated settings drift] → reuse the same editors and APIs.
- [Stale completion] → recompute readiness and invalidate reviews when the underlying settings change.
- [External services unavailable] → show the exact missing verification; do not block human helpdesk use on an absent AI service.

## Migration Plan
New setup metadata defaults to unreviewed; existing accounts can continue using the helpdesk and open setup voluntarily. No forced redirect or interruption of current conversations.
