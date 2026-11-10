## Why
The broad order-actions grant prevents a merchant from allowing address changes while withholding refunds or cancellation. The founder accepted separate staff rights on 2026-11-09.

## What Changes
- Grant each existing Shopify action independently, with administrator-only management and server enforcement in dialogs, previews, macros and retries.
- Preserve existing broad order grants as the corresponding explicit action set; new staff have no write rights. Keep existing discount grants independently effective.
- Show the action matrix and accurate unavailable states, including failed saves.
- Require refund rights for a cancellation that refunds. **BREAKING:** a newly requested discount on a draft order additionally requires the separate discount right.

## Capabilities
### New Capabilities
- `staff-action-permissions`: Independent grants and common enforcement for all existing actions.
### Modified Capabilities
- `order-creation`: Require new-order authority and discount authority when adding a discount.
- `macro-order-actions`: Enforce the corresponding current rights for every macro step.

## Impact
Overlay migrations/models, action runner, panel responses, admin settings and conversation controls; existing APIs retain aggregate fields and administrator-only legacy grant endpoints. No change to Shopify app scopes or deployment.
