## Context

See proposal.md. The integrated tree combines foundation, reply variables, store data rules, tags/notes, macros, new orders, item editing, reply inserts, SLA and the AI connector. The original working tree contains unrelated uncommitted work and must not be used for acceptance edits.

## Goals / Non-Goals

**Goals:** establish observable behavior of the combined product and make defects reproducible. Distinguish implementation, automated coverage, live execution and visual review.

**Non-Goals:** deciding the AI authority model on the founder's behalf; assuming all features marketed by upstream Chatwoot are available in CE; equating Shopify API success with a customer having received an email; deploying the merchant pilot.

## Decisions

1. Use a separate clone, branch, image and database. This permits checking integrations without changing the current dev instance or feature worktrees.
2. Preserve existing runner concurrency and idempotency fixes during merges. Reading a panel must not replay order mutations. Verify lost-response paths with regression tests and development-store fault injection.
3. Use a separate Shopify app to verify the changed order, totals, refunds and stock. This avoids validating the helpdesk against its own cached response.
4. Capture screenshots only after credentials have left the screen; keep traces and test credentials private. Visual evidence must be inspected, not merely generated.
5. Record native Chatwoot capabilities separately from exercised end-to-end scenarios. External channel delivery needs the channel connection; an API inbox does not prove email, WhatsApp or SMS delivery.

## Acceptance baseline and gaps

The founder's eight-page comparison dated 2026-11-04 covers Gorgias, Commslayer, Richpanel, Re:amaze and eDesk. Its 16 live checks distinguish verified behavior from vendor claims; Shopify order actions and AI actions were not exercised in that research. Use its helpdesk, AI and UI/UX tables as the baseline, supplemented by the primary references checked on 2026-11-09 below:

| Area | Competitor evidence | Integrated helpdesk and remaining evidence |
|---|---|---|
| Orders, cancellation, refunds, address, creation, duplication, product links | [Gorgias Shopify actions](https://helpcenter.gorgias.com/en-US/shopify-actions-461552) | Implemented paths and browser suites exist; require a combined live run and shopper verification. |
| Tags, notes, edit totals, invoice/refund difference, permissions and action history | [Commslayer order actions](https://docs.commslayer.com/en/articles/1791169032-refund-edit-and-duplicate-shopify-orders-from-a-conversation) | Implemented; staff rights are currently one order-actions switch plus separate discount grants. Granular staff rights are missing. |
| Fulfillment hold/release, store credit, custom items, line discounts and shipping edits | Same Commslayer reference | Gaps or explicitly excluded item-editing scope. Do not label these supported or silently change earlier scope decisions. |
| AI cancellation, address confirmation, item removal/replacement | [Gorgias AI actions](https://helpcenter.gorgias.com/en-US/ai-agent-actions-make-changes-to-shopify-orders-757792) | Connector handles conversations and handoff. No AI order-action policy or order-action API has been implemented. Requires a separate approved change. |
| Shared inbox, assignment, notes, labels, search/filter, templates/macros, business hours, reports and knowledge base | [Chatwoot feature catalogue](https://www.chatwoot.com/features/) | Inspect pinned CE source and run smoke scenarios. Catalogue includes paid features and is not evidence of inclusion in this image. |
| Collaboration and templates | Five-vendor comparison, sections 1 and 6 | Native notes, mentions/notifications, assignment, search, snooze and canned responses; verify in the combined image. Bulk actions, merge/split and collision indicators are not covered by this run. |
| Help center and reports | Five-vendor comparison, sections 1 and 6 | Native CE implementation exists. Verify public published articles vs private drafts and basic report counts/dashboard. This is not full analytics or self-service order-editing acceptance. |
| AI controls, drafts, approval and monetary limits | Five-vendor comparison, section 2 | Proposed behavior remains undecided. The connector test double establishes transport/handoff only, not model quality or safe autonomous Shopify actions. |
| Onboarding | Existing connect-store dialog and admin settings | Store setup is entered through a conversation; no complete setup flow covering store, channels, staff rights, AI authority and a verified test order. |

Minimum scenario groups: paid/unpaid cancellation; partial/full refund and restock; address change before/after shipment; add/remove/change quantity and the resulting amount due; invoice/payment link; replacement; ambiguous customer and a different person's order; revoked rights; repeated request; lost/late response; Shopify refusal; missing scope; AI off/disconnected/handoff; closed/reopened/snoozed conversation; private note visibility; assignment and search; laptop and narrow viewport.

For each live order scenario, keep the input, actor/role, expected state, helpdesk action record, independent Shopify state and available shopper-facing evidence. An invoice event proves Shopify accepted sending, not mailbox receipt. A payment URL must be opened and checked separately. Real payment settlement is outside a development store's evidence.

## Visual defects found during acceptance

- At 1024 px, four columns left the reply editor approximately 164 px wide. Use upstream expanded conversation/back navigation below 1280 px without persisting a different user preference; verify a usable composer and return to the list in the browser.
- The connection dialog omitted the scopes for item edits and discount codes, and mentioned draft orders only for replacements. Correct the instruction to match the installed actions.
- A failed role save left the checkbox optimistic and showed no failure. Restore the last confirmed value and show an inline error; a real browser test injects a 503 to verify it.
- Discount grants and preset removal, and SLA reorder/removal, also lacked failure feedback. Preserve the confirmed values, show an alert and allow retry; five regression cases failed before the fix and passed after it.
- Shopper screenshots taken before the content assertions showed loading placeholders. Capture only after the actual address/cancellation/items and totals are visible.
- Visual review of the real checkout exposed a money mismatch: the helpdesk quoted UAH 1,585.90 with no shipping charge, while checkout added UAH 500. The test had matched the subtotal anywhere on the page. Existing order-creation behavior permits no shipping charge or an entered amount; represent no charge with an explicit zero-priced custom shipping line in both preview and creation. The corrected browser checks passed for the actual Total row and shipping summary: UAH 1,585.90 with free shipping and UAH 1,590.90 with UAH 5 shipping. Shopify fixes the shipping address when a custom shipping line is supplied; this is visible in the shopper screenshots. [Shopify ShippingLineInput](https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ShippingLineInput) documents custom rate title and price.
- The direct cancellation dialog explains irreversibility and refund/restock/notification choices, but does not show the refund amount in that confirmation. Record this as a UX follow-up; do not confuse the order card's amount with a fresh cancellation preview.

## Remaining native help-center defect

The real anonymous-browser check successfully opened a published article, then received HTTP 200 for a draft article at its direct public URL. The pinned CE source explicitly tests this behavior and its editor's Preview button opens that URL. The privacy acceptance test remains failed: hiding a draft from search is not access control. A follow-up must introduce an authorized editor preview and deny anonymous access to unpublished content together; simply denying the URL would remove the current preview workflow. This is not reported as passed or silently waived.

## Risks / Trade-offs

- [Branches passed separately but conflict when combined] → preserve regression tests, run the integrated frontend/backend suites and then the complete browser suite.
- [Dev-store write throttles and eventual indexing] → existing paced seeding and bounded waits; no parallel order mutation workers.
- [Competing work on the dev machine] → respect server locks, use isolated paths and do not remove another session's lock.
- [Unanswered policy question] → continue independent acceptance work and leave new AI/staff behavior unimplemented until the founder answers.

## Migration Plan

No production migration or pilot deployment in this change. Preserve integration commits and review artifacts. Clean tagged Shopify test resources and the isolated temporary stack after testing. A later deployment selects the reviewed image explicitly.
