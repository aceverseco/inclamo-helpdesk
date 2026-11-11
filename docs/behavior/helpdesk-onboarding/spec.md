# helpdesk-onboarding

Behavior contract for this source revision.

### Requirement: Resumable administrator setup

Administrators SHALL reach setup directly from settings without creating a conversation. Setup SHALL cover store connection, channels and team, staff action rights, AI policy and verification. It SHALL use the same persisted values as the later settings pages and resume after navigation or reload. Staff SHALL not change account setup. A connection failure or failed setting save SHALL remain visible and SHALL not mark its step complete.

#### Scenario: Connect before a conversation exists

- **WHEN** a new account administrator opens setup
- **THEN** they can connect Shopify and review rights without an existing ticket

#### Scenario: Resume settings

- **WHEN** the administrator leaves setup after saving staff rights and returns
- **THEN** the saved rights remain and can also be edited from normal settings

### Requirement: Readiness reflects actual prerequisites

Completion SHALL require a working Shopify connection, at least one configured channel and explicit review of staff rights and AI policy. A human-operated helpdesk SHALL be allowed to complete without an AI service, with that state clearly stated. Setup SHALL provide a connection recheck and a path to a test conversation/order scenario, clearly distinguishing technical readiness from verified mail delivery, real model behavior or a completed test order. Losing a required connection SHALL be reflected when setup is opened again.

#### Scenario: Missing channel prevents completion

- **WHEN** the administrator tries to complete setup without a channel
- **THEN** the missing channel is shown and setup is not complete

#### Scenario: Human-operated setup

- **WHEN** store and channel prerequisites pass and the administrator reviews staff and AI defaults without connecting AI
- **THEN** setup can complete and explicitly states that AI is not connected

#### Scenario: A working connection is not a completed order test

- **WHEN** the Shopify connection check succeeds but no test action has been verified
- **THEN** setup shows the connection as working and the order scenario as not yet verified
