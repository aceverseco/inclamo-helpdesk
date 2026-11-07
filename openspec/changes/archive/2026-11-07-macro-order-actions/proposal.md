## Why

The commonest tickets end the same way: refund and say sorry, cancel and confirm, reship and give the new tracking. Today that is a dialog in the panel plus a saved reply, each by hand. Three of the five e-commerce helpdesks this project is measured against let a macro perform the order action together with the message, the label and the status.

## What Changes

- Four **order steps in the macro editor**: "Refund the order in full", "Refund the shipping cost", "Cancel the order", "Send a free replacement". Each has a fixed behaviour stated in its description; they act on the order tied to the conversation.
- **Confirmation before a macro with order steps runs**, naming the order and what will happen to it.
- **A failed order step stops the macro**: the message "we refunded you" never goes out when the refund did not happen. The agent sees which step failed and why.
- Order steps run only for an administrator or an agent holding the order-actions role, and leave the same record as the manual action.
- One new seam in Chatwoot's dashboard: the list of macro steps and the moment before a macro runs become extensible, carried as a patch.

Not in this change: order steps in automation rules (no order action runs without a person), steps with adjustable options, a step for the address change.

## Capabilities

### New Capabilities
- `macro-order-actions`: which order steps a macro can contain, on which order they act, who can run them, what is confirmed, what happens on failure and what record is left.

### Modified Capabilities
- none.

## Assumptions to confirm

1. The steps have fixed behaviour, no options: full refund without restocking with the store's notification; cancellation with full refund, restocking and notification; replacement with the same items to the same address.
2. A macro with an order step asks for confirmation once before it runs. The other helpdesks run such macros without asking; here every money action asks, so macros do too.
3. The steps act on the tied order only, never on "the customer's last order".

## Impact

- Backend: four macro actions that call the existing action runner; the macro's step loop stops after a failed order step.
- Dashboard: seam 4 (macro steps registry and a before-run hook), our entries and a confirmation dialog.
- No new Shopify scope: the steps need what the manual actions need.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
