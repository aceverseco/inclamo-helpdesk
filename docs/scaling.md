# Scaling an installation

No tenant capacity or automatic scaling configuration is supplied by this
repository. Size an installation from measured request rate, concurrent staff,
message and attachment volume, queue age and external-service latency.

## Shared state and workers

Run Rails web/WebSocket processes and Sidekiq workers as separately sized
services. Multiple replicas need shared PostgreSQL, Redis and durable object
storage for attachments; a replica-local upload directory is insufficient.
Keep encryption keys stable across replicas and restores. Budget database
connections across all web and worker pools, with operational headroom.

The overlay uses session advisory locks. Verify lock lifetime and connection
routing before using transaction-mode database pooling. Do not hold a database
connection while waiting for external model inference.

Sidekiq jobs can execute more than once. Use stable operation IDs, bounded
retries and reconciliation for uncertain remote outcomes. Keep interactive
queues available when exports, mail or background rules are busy.

## AI service integration

The external service must durably accept events before acknowledging them,
deduplicate within the installation/account/connection scope and bound work
per merchant. In-memory simulator queues are intended for tests. A restart
after acknowledgement must not lose a customer turn or repeat a financial
action. See the [integration contract](service-integration.md) for handover,
late-result handling and recovery requirements.

Budget native API requests per destination and egress IP, and Shopify requests
using the returned GraphQL cost and throttle information. Measure lock waits,
DB pool occupancy, oldest queue age, request errors and reply latency alongside
CPU and memory. Adding replicas alone does not remove these bottlenecks.

## Deployment validation

Measure sustained and burst load with representative synthetic data. Include
one busy tenant, slow external services, worker loss and Redis/database recovery.
Record image and configuration versions with measurements. Verify isolation,
bounded queue growth and absence of lost acknowledgements or repeated actions.

Back up database contents, encrypted credentials and attachment storage as one
recoverable installation. Test restoring into an isolated environment and
reconcile pending or uncertain operations. Release immutable images with
compatible migrations and graceful worker draining; rollback must preserve
deduplication and operation identifiers.
