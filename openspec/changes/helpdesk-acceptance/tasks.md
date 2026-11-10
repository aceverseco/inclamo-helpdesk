## 1. Integrated build

- [x] 1.1 Combine implemented feature branches in an isolated clone; verify original worktrees are untouched and all six patches assemble, including the laptop layout correction.
- [x] 1.2 Check Shopify documents, fixture schemas and UI strings; verify 77 GraphQL documents and 54 fixtures pass.
- [x] 1.3 Fix the settings import cycle and permission-save feedback; verify 264 overlay and 381 upstream frontend cases across the baseline and targeted reruns.
- [x] 1.4 Resolve backend integration defects; verify 741 overlay examples across the baseline and targeted reruns (including 59/59 in the shipping-affected group) and 120/120 upstream regressions. Two invalid new test identifiers were corrected and their group rerun 22/22.
- [x] 1.5 Build the combined image; verify image creation and startup of its own database and app.

## 2. Acceptance execution

- [x] 2.1 Run the combined Shopify browser suite; report passed, failed, skipped and unexecuted scenarios and verify cleanup.
- [x] 2.2 Inspect screenshots of setup, roles, order cards, confirmations, errors and narrow layouts; record concrete UX defects.
- [x] 2.3 Open the shopper's payment/order view for test orders; verify changed items, totals and cancellation where exposed, and distinguish this evidence from API/event checks.
- [x] 2.4 Exercise native helpdesk essentials in the assembled CE image; record the failed draft-privacy check and any untested external channel integrations explicitly. Execution is complete when results are recorded, not when every case passes.

## 3. Review handoff

- [x] 3.1 Compare the implementation with primary competitor documentation; record capability and evidence gaps in design.md.
- [x] 3.2 Deliver a reviewable acceptance report with test results, screenshots, remaining defects and the pending permission/onboarding decisions; do not mark the product ready with missing evidence.

## Recorded outcome (2026-11-09)

- 190 distinct browser cases: latest results are 189 passed and one failed (anonymous access to a draft help article). Results combine the baseline and targeted reruns; they are not one fully green run.
- Shopify shopper views confirm changed address, cancellation, edited quantity/total, and matching checkout totals with free and paid shipping. Merchant data was checked independently through Admin API, not through an authenticated Shopify Admin browser.
- Read-only cleanup audit found zero remaining run-tagged orders, customers, products, drafts or discounts across all four Shopify-writing runs. The reports-only run creates no Shopify resources.
- Report, sanitized evidence and a complete Git bundle are delivered in the company workspace at `reports/helpdesk-acceptance-2026-11-09/`. The report lists missing AI authority, granular staff rights, full onboarding, protected draft preview and untested external channels.
