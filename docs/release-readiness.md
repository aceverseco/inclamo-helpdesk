# Release capabilities and limitations

This source provides a Chatwoot Community Edition overlay with Shopify order
workflows, operation-specific staff permissions, AI action proposals and policy,
setup settings, order templates/macros/rules and SLA timers. Build and test the
source revision you intend to deploy; a development build does not establish
that a hosted service or its external dependencies are operational.

## Integrations

- The AI connector exposes the versioned [wire contract](ai-connector.md).
  The included deterministic simulator tests that contract; it is not a
  production model or proof of model quality.
- Validate receipt, reply threading and sender identity with the mailbox
  provider configured for your installation. Validate transaction-email
  delivery separately from inbox configuration.
- A Phone inbox does not enable telephony. Finished-call ingestion, automated
  hosted provisioning, Shopify OAuth and Shopify sign-in are not provided by
  this source revision.
- Automatic tenant-count-based scaling and capacity at thousands of merchants
  have not been established. See [scaling guidance](scaling.md).

## Validation

[CI](../.github/workflows/ci.yml) checks the overlay and its upstream integration
points. [Behavior contracts](behavior/README.md) are matched to end-to-end tests.
Run service-specific integration tests before enabling an external AI service;
the procedure and recovery cases are in [service integration](service-integration.md).
Test backups, restores and rollback with your own storage and encryption setup.
