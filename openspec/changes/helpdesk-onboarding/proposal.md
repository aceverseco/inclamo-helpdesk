## Why
Store setup currently begins inside a conversation and new administrators cannot review staff/AI authority as a coherent setup flow. The founder accepted these controls during onboarding and later in settings.

## What Changes
- Add a resumable administrator setup page covering Shopify connection, channels/team, staff action rights, AI authority and readiness verification.
- Reuse the same persisted controls as settings; show defaults, failures and missing prerequisites explicitly.
- Check a working store connection, at least one channel and explicit review of staff and AI settings before completion; AI connection is optional for a human-operated helpdesk.
- Provide a test-conversation entry and distinguish a connection check from a completed test order/action.

## Capabilities
### New Capabilities
- `helpdesk-onboarding`: Resumable setup and honest readiness state with shared rights/policy controls.
### Modified Capabilities
None.

## Impact
Depends on staff-action-permissions and ai-order-authority. Adds setup status/API and route with reusable settings components; uses the installed store-connection mechanism. Existing separately planned Shopify OAuth/sign-in and hosted pilot deployment are unchanged.
