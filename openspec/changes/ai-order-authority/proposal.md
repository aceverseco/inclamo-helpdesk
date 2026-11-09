## Why
The AI connector currently has no governed way to propose or execute Shopify changes. The founder accepted independent forbidden/propose/autonomous modes, with staff approval by default and explicit limits for autonomous execution.

## What Changes
- Administrator policy per existing Shopify operation, defaulting to propose; autonomous mode requires amount and order-state restrictions where applicable.
- Bot-token endpoints for order context, proposals and governed execution, scoped to the connected account, inbox and conversation customer.
- Immutable proposals reviewed in the conversation; an authorized staff member approves the exact current summary or rejects it. Permission, connection, customer and order changes are rechecked.
- Record AI initiator, human approver, policy and final action outcome; duplicate submissions cannot duplicate a mutation.
- Provide deterministic request and browser coverage without claiming acceptance of an unavailable real AI service.

## Capabilities
### New Capabilities
- `ai-order-authority`: Policies, scoped AI order context, proposals, approval and autonomous guardrails.
### Modified Capabilities
None.

## Impact
Depends on staff-action-permissions. Adds policy/proposal storage, scoped endpoints, server authorization, AI settings and conversation review UI; extends the connector contract without replacing bot-token authentication. Subscription/service integration remains the existing separate AI service contract.
