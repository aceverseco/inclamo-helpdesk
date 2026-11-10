# Scaling the helpdesk and its AI integration

Engineering target, 2026-11-10. **Capacity at thousands of merchants has not
been measured.** This document defines a design and proposed release gates;
it does not certify the current build or select a cloud size. Merchant count
alone says little without message rate, concurrent staff, order volume,
attachment traffic and model latency.

## Boundaries and placement

Keep channel ingress, helpdesk web/WebSocket traffic, background jobs and AI
inference in independently sized worker pools. One merchant must not occupy
all inference slots, database connections or outbound requests. Pairing and
connection lifecycle belong to a control plane; message processing uses a
cached, revocable connection binding and does not call onboarding on every turn.

Support an installation registry from the start: installation identity and
origin, account ID, connection generation, region/cell and credential reference.
Store and conversation keys must include their tenant scope. A dedicated
merchant installation is compatible with this model. A later shared deployment
can use bounded cells (a group of tenants sharing an independently operated
stack), with large tenants moved to a separate cell. Cell sizing, migration
tooling and routing are future operational work, not implemented here.

Each cell needs separately scaled Rails and Sidekiq processes, persistent
PostgreSQL, durable Redis queues and shared object storage for attachments.
Replicas cannot rely on a local upload directory. Keep encryption keys stable
across replicas and restores. Size database pools against the **sum** of web,
worker and operational connections with headroom. The overlay uses session
advisory locks: transaction-mode connection pooling is not a drop-in replacement
for its database connections. Verify lock lifetime and routing before adopting
a pooler. Avoid a database connection held while waiting for model inference.

## Durable processing and bounded retries

Use a transactional inbox and work table, or an equivalent durable broker with
an explicit recovery strategy. Commit event deduplication and its work reference
in the same transaction before the webhook acknowledgement. A database
"seen" row plus an in-memory promise loses work after a crash. A database row
and separate broker enqueue also need an outbox/reconciliation mechanism.

Lease work with expiry and a fencing generation so a restarted worker cannot
write after its successor. Serialize by connection + conversation, not by
global process. Tenant-aware admission and scheduling enforce per-merchant
concurrency, queue depth and maximum queue age alongside global ceilings.
Expired work hands over; it does not produce an answer minutes later beneath
a human agent. Control/status events need reserved capacity during a message
flood. Store durable identifiers instead of full webhook transcripts where the
history can be refetched; retention must cover the replay/recovery window.

All side effects need stable operation IDs and explicit uncertain outcomes.
Sidekiq itself provides at-least-once execution, so jobs must tolerate repeats;
queue selection alone does not prevent a second refund or reply.
[Sidekiq best practices](https://github.com/sidekiq/sidekiq/wiki/Best-Practices).

Retry safe reads and known-not-applied actions with exponential backoff, jitter,
a maximum attempt count and an overall deadline. Quarantine terminal failures
with a replay procedure that preserves original IDs. Keep the existing helpdesk
webhook retry behavior (contract §2.1) distinct from the new service's internal
retry policy. Recovery after an acknowledged event is the receiver's duty.

## Limits to measure in this build

| Constraint | Required response |
| --- | --- |
| Native API default 3,000 requests/minute **per IP** | Budget requests per destination installation and shared egress IP; reserve capacity for handover. Do not simply disable the limit. |
| Shopify GraphQL budget per app/store | Pace using returned cost/throttle metadata; one throttled store must not pause other merchants. Do not retry an unknown mutation as a new action. |
| Proposal execution uses an account advisory lock | Measure busy rate, lock duration and DB pool occupancy during slow Shopify calls; retry the same request with a deadline. |
| Responder/model throughput and provider quotas | Bound active turns, input history, attachment work and output tokens; enforce per-merchant and global budgets. |
| Helpdesk history/files and list queries | Test with realistic historical rows and large conversations; inspect query plans and indexes before adding replicas. |
| Email, exports, rules and SLA background work | Reserve interactive worker capacity; avoid mass mail or exports starving inbound messages and handovers. |

Shopify budgets are cost-based and scoped to app/store; read the response's
current throttle information rather than hard-coding one plan's allowance.
[Shopify API limits](https://shopify.dev/docs/api/usage/limits).

For an illustrative load of 100 shopper messages/second and six helpdesk API
calls per turn, a single destination would receive 36,000 calls/minute from a
shared egress, above the current 3,000 default. At an eight-second mean turn,
Little's law gives roughly 800 active turns. These are planning calculations,
not measured traffic or a server sizing recommendation.

## Proposed capacity acceptance profile

Start with 1,000 synthetic merchant bindings and 100,000 historical conversations;
repeat with 5,000 bindings and 1 million conversations. Include two independent
installations with the same account/conversation IDs. Publish machine sizes,
replica counts, queue/DB settings, image and source hashes alongside results.

| Exercise | Load and proposed pass condition |
| --- | --- |
| Steady ingress | 100 incoming shopper messages/s for 60 min, plus generated status/outgoing events; durable acknowledgement p95 <250 ms and p99 <1 s; no lost acknowledged events |
| Burst | 300 shopper messages/s for 5 min, then baseline; bounded queues, explicit overload handling, backlog drained within 10 min without exceeding turn deadlines |
| Noisy merchant | One merchant sends 50% of traffic; other merchants' queue-age p95 <2 s and latency regression <20% against baseline |
| Operator workload | 200 concurrent synthetic staff sessions opening lists/conversations, searching and taking over; API p95 <500 ms excluding external services, measured separately from browser rendering |
| Soak | 24 h at 50 shopper messages/s; no sustained backlog or connection leak; memory stable after warm-up and bounded dedupe retention |
| Availability faults | Kill receiver after commit/before response and worker before/after every side effect; restart Redis/DB, revoke bot, exhaust model quota, throttle Shopify; zero cross-tenant operations and zero repeated financial effects |
| Recovery | Restore database, encrypted credentials and attachments into an isolated environment, reconcile queued work and uncertain writes; proposed RPO ≤5 min / RTO ≤60 min, proven by a timed drill |

Run load against synthetic stores and a deterministic delayed responder first.
Emit valid signatures, duplicate deliveries and authentic event amplification;
an unsigned health-check benchmark does not measure this path. Then run a
separately bounded real-model sample with recorded token/cost budgets. Do not
load-test production Shopify orders or customer mailboxes. End-to-end customer
latency is measured separately; inference must fit the adapter's turn deadline
with time left for reads, writes and handover.

Observe accepted, queued, started, completed, handed-over and unresolved counts
so their reconciliation detects loss. Track oldest job age, retry/dead-letter
age, DB pool wait, lock wait, memory, API 429s, model quota and reply latency.
Keep merchant IDs in structured traces and scoped reports; avoid an unbounded
tenant/message-ID cardinality in every metric. Alert on oldest work and failed
handover, not just process uptime. Logs must not contain tokens, pairing codes,
raw webhooks or customer order data.

## Rollout and rollback

Release by immutable image digest with additive, compatible migrations, health
checks and bounded graceful draining. Start on disposable tenants, then one
pilot, then cohorts of 10/100/1,000 only after each cohort's measured gate.
Capacity at 1,000 does not establish capacity at 5,000. Disable the AI connection
and hand over its pending work when a cohort fails; the human helpdesk remains
the fallback. A deployment rollback must preserve deduplication/action IDs and
must not replay already applied financial writes. Recovery drills and at least
one replica-loss test precede any availability claim.
