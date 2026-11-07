## Why

Agents mark orders and customers as they work: "address confirmed", "fraud check", "wholesale", a note for the warehouse. Today that means a second tab with the Shopify admin. Four of the five e-commerce helpdesks this project is measured against let the agent read and change tags and notes beside the conversation.

## What Changes

- The order card shows the order's **tags and note**; the customer block shows the customer's **tags and note**.
- An agent with the order-actions role can **add and remove tags** and **edit the note** of the order and of the customer.
- Customer tags and note need one more permission of the merchant's app, `write_customers`; without it they are shown but cannot be changed, and the panel says why.
- Every change leaves a private note in the conversation.

Not in this change: tags in bulk, tag suggestions, metafields.

## Capabilities

### New Capabilities
- `order-tags-and-notes`: what the panel shows of tags and notes, who can change them, which permission each change needs, and what record a change leaves.

### Modified Capabilities
- none.

## Assumptions to confirm

1. Changing tags and notes needs the same order-actions role as refunds and cancellations: one role for everything that changes the store.
2. Tags and notes are saved at once, without the confirmation step the money actions have.

## Impact

- Backend: two new actions in the existing action runner (tags, note) for orders and customers; new GraphQL documents.
- Dashboard: tag chips and a note field in the existing order card and customer block; no new seam.
- Shopify scopes: `write_orders` (already used) for the order; **`write_customers` (new, optional)** for the customer. The connection guide and the test apps get the new scope.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
