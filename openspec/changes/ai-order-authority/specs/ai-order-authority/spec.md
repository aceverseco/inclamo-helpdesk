## Purpose
Let a merchant control and review AI-requested Shopify changes with explicit authority, bounded autonomous execution and an auditable outcome.

## ADDED Requirements

### Requirement: Administrator configures AI authority
Each operation SHALL have forbidden, propose and autonomous modes independent of staff rights. Its default SHALL be propose. Only an administrator SHALL change policy. Autonomous mode SHALL require explicit allowed order states for order actions and monetary limits for operations involving orders or discounts; limits SHALL identify their currency and meaning. Missing or invalid limits SHALL prevent autonomous execution. Policy changes SHALL be visible in settings and onboarding.

#### Scenario: Default requires a person
- **WHEN** a connected bot requests an eligible action with no saved policy override
- **THEN** a proposal awaits staff confirmation and Shopify is unchanged

#### Scenario: Refuse incomplete autonomous policy
- **WHEN** an administrator selects autonomous refunds without a valid amount limit or allowed states
- **THEN** the policy is not saved and the UI explains the missing restriction

### Requirement: Bot authority is scoped to its active conversation
Only the current connected bot SHALL request order context or actions for its connected inboxes. It SHALL not execute autonomously after handoff, disconnect, replacement by another bot, or loss of subscription/service access. Targets SHALL belong to the conversation's unambiguously matched customer. Unverified or ambiguous shopper identity SHALL require human review before an autonomous change. Bot input SHALL never supply staff authority or bypass store scopes.

#### Scenario: Another customer's order
- **WHEN** a bot requests a change to an order belonging to a different customer
- **THEN** the request is refused and no mutation occurs

#### Scenario: Human takes over
- **WHEN** a conversation is handed to staff before an autonomous action executes
- **THEN** autonomous execution is refused

### Requirement: Staff reviews an immutable proposal
A proposal SHALL identify the requested action, target, requested changes, current monetary effect and expiry. It SHALL change nothing until an authorized staff member confirms it. Staff without every required permission SHALL not approve. Rejection SHALL perform no mutation. Approval SHALL apply only to the exact proposal shown, after rechecking permissions, policy, connection, customer and current Shopify state; changed facts SHALL require a refreshed review instead of silently changing the confirmed outcome.

#### Scenario: Confirm with the right permission
- **WHEN** authorized staff confirm a current proposal
- **THEN** the exact action executes once and the record identifies both the bot and the approving person

#### Scenario: Stale review or revoked permission
- **WHEN** the order changes or the person's required permission is revoked after review
- **THEN** confirmation cannot silently execute the former proposal

#### Scenario: Reject or expire
- **WHEN** staff reject a proposal or attempt to approve it after expiry
- **THEN** Shopify is unchanged and the UI reports its status

#### Scenario: AI item edit is reviewed and verified by the shopper
- **WHEN** staff with item-edit permission approve the bot's exact quantity change
- **THEN** the reviewed items and total are saved once and appear in Shopify and the shopper order view

#### Scenario: AI cancellation requires both rights and returns the reviewed amount
- **WHEN** staff approve a cancellation with a refund
- **THEN** both cancellation and refund permission are required and the reviewed refund and cancellation are independently verified in Shopify and the shopper order view

#### Scenario: AI item refund names the product and verifies the refunded amount
- **WHEN** staff review a refund for selected items
- **THEN** the proposal names those products and quantities, the payment destination and actual restocking result, and approval refunds the reviewed amount once

### Requirement: Autonomous execution obeys current restrictions
Autonomous actions SHALL pass the same ownership, state, scope, eligibility and idempotency checks as approved actions. Amounts SHALL be calculated from current Shopify data, never trusted from bot assertions. Exceeding any configured bound SHALL prevent mutation and expose a reason. Compound operations SHALL also satisfy the policy of their financial component. The action record SHALL distinguish proposed, approved, rejected, accepted, refused and unknown outcomes; an unknown outcome SHALL not be described as success.

#### Scenario: Refund above the configured amount
- **WHEN** the requested refund exceeds the current policy limit
- **THEN** no refund is sent to Shopify

#### Scenario: Duplicate AI request and approval
- **WHEN** the same request or approval arrives twice, including concurrently
- **THEN** at most one Shopify mutation occurs and the existing result is returned

#### Scenario: Lost Shopify reply
- **WHEN** Shopify may have acted but its reply is lost
- **THEN** the UI and AI response report an unknown outcome until independently resolved
