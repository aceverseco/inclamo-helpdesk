## 1. Integrated build

- [x] 1.1 Combine implemented feature branches in an isolated clone; verify original worktrees are untouched and all five seam patches assemble.
- [x] 1.2 Check Shopify documents, fixture schemas and UI strings; verify 76 GraphQL documents and 54 fixtures pass.
- [x] 1.3 Fix the settings import cycle; verify all existing frontend cases plus the affected settings cases pass across the baseline and targeted rerun.
- [x] 1.4 Resolve backend integration defects and verify the complete backend run plus any necessary targeted rerun pass (737 examples: two new test identifiers corrected; affected group rerun 22/22).
- [ ] 1.5 Build the combined image; verify image creation and startup of its own database and app.

## 2. Acceptance execution

- [ ] 2.1 Run the combined Shopify browser suite; report passed, failed, skipped and unexecuted scenarios and verify cleanup.
- [ ] 2.2 Inspect screenshots of setup, roles, order cards, confirmations, errors and narrow layouts; record concrete UX defects.
- [ ] 2.3 Open the shopper's payment/order view for test orders; verify changed items, totals and cancellation where exposed, and distinguish this evidence from API/event checks.
- [ ] 2.4 Exercise native helpdesk essentials in the assembled CE image; record any untested external channel integrations explicitly.

## 3. Review handoff

- [x] 3.1 Compare the implementation with primary competitor documentation; record capability and evidence gaps in design.md.
- [ ] 3.2 Deliver a reviewable acceptance report with test results, screenshots, remaining defects and the pending permission/onboarding decisions; do not mark the product ready with missing evidence.
