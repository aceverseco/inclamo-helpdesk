# Integrated development build: acceptance record

2026-11-10. Functional source baseline: `8818e577b9cb1e9d20d153fc463d6f54a366e594`.
This publication consolidates the feature branches and acceptance fixes. It is
an integration build, not a declaration that a hosted production service is live.

## Recorded verification

The November 9 acceptance run used isolated helpdesk accounts and tagged orders
in a Shopify development store. Counts below summarize that run and targeted
rechecks, not a fresh run performed solely for this documentation publication.

| Scope | Recorded result |
| --- | --- |
| Browser scenarios | 218 distinct scenarios passed across the full run and targeted rechecks; the initial run had one fixture-indexing delay, subsequently passed |
| Overlay backend | 786 distinct examples, including the final refund case |
| Overlay dashboard | 277 distinct component tests, including the final refund case |
| Affected upstream behavior | 120 backend examples and 381 dashboard tests |
| Shopify documents / sanitized fixtures | 77 valid GraphQL documents / 54 checked fixtures |
| Deterministic AI service | 8 contract tests |

Covered behavior includes operation-specific staff rights; forbidden, proposed
and bounded autonomous AI actions; setup settings; human takeover; identity and
scope refusal; address/item edits, cancellation and refund; outcome reconciliation;
and shopper-facing order/payment views. Shopify changes were independently read
back through the Admin API. Test resources were cleaned up. The shared development
installation was not replaced by these isolated acceptance runs.

Publication preparation additionally replaced recorded order-status URL paths
and authentication queries in fixtures with a wholly synthetic URL and added
a fixture check that refuses their reintroduction. The behavior tests read the
URL from the fixture; no runtime order link is changed.

## Remaining acceptance

- Production AI adapter and real-model intent/tool quality, including faults
  after acknowledgement and across multiple workers.
- Merchant mailbox receive/reply, actual transaction email receipt and delivery
  monitoring. A configured inbox alone is not email acceptance.
- Browser review inside Shopify Admin, in addition to the completed API readback.
- Finished-call ingestion, hosted provisioning, Shopify OAuth connection and
  Shopify sign-in: separate pending changes, not features implied by this build.
- Competitor coverage beyond the accepted order workflows: comprehensive bulk
  actions, merge/split, concurrent-agent behavior and reporting acceptance.
- Capacity and recovery gates in [scaling.md](scaling.md).

The separate workspace snapshot preserves unfinished design work and historical
visual evidence. It is not part of the functional baseline above. Its patch
sequence and final visual acceptance must be reconciled with this integrated
branch before deployment. Start service integration with
[service-integration.md](service-integration.md) and the versioned wire contract.
