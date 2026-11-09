## Context
See proposal.md and the recorded defects in helpdesk-acceptance/design.md.
## Goals / Non-Goals
Protect unpublished content while keeping the editor workflow. Show actual cancellation/refund information. No change to publishing permissions or Shopify payment settlement.
## Decisions
- Public article reads require publication or a signed article/account-specific preview token, valid for five minutes. Issue tokens only through authenticated account-scoped authorization; previews use no-store and no-referrer headers. Direct anonymous draft links return 404.
- The editor opens a tab during the click, obtains the preview URL asynchronously, and closes the tab with visible error feedback if authorization fails.
- Cancellation confirmation loads the common runner's fresh cancellation preview. While a refund amount is unknown or loading, confirmation remains disabled; retry and cancelling without refund remain available. Staff without refund permission see the refund option disabled.
## Risks / Trade-offs
A preview URL is a temporary bearer capability: keep it short-lived, article-scoped and out of referrers/caches. A Shopify preview is a point-in-time calculation; existing action preconditions still run on execution.
## Migration Plan
No data migration. Apply overlay extension and pinned editor patch; exercise public and editor views and cancellation dialog before final image review.
