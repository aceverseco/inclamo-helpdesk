## Why

"Please remove the second mug" and "make it two instead of one" are everyday requests between payment and shipping. Today the agent has to cancel the order and build a new one, or leave for the store's admin. Two of the five e-commerce helpdesks this project is measured against edit the items of an order from the conversation, a third partly. This was planned for release 0.2 and was moved up by the founder's decision of 2026-11-06.

## What Changes

- **"Edit items"** on an order that still has unshipped items: change a quantity, remove an item, add a product from the catalogue.
- Before saving the agent sees **what changes in money**: the customer owes more, money is due back, or nothing changes, as the store calculates it.
- On saving: the store can notify the customer; when the customer owes more, the store can email an invoice for the balance; when money is due back, the agent is led to the refund dialog with that amount.
- Needs one more permission of the merchant's app, `write_order_edits`.

Not in this change: editing shipped items, changing prices of existing lines, changing the shipping method.

## Capabilities

### New Capabilities
- `order-item-editing`: which orders and lines can be edited, what the agent sees before saving, what happens with the money difference and the stock, who may edit and what record it leaves.

### Modified Capabilities
- none.

## Assumptions (confirmed by the founder on 2026-11-06)

1. An unshipped item taken off an order goes back to stock always, without a checkbox: it never left the shelf.
2. Money due back is not refunded by the edit itself; the agent confirms the refund in the existing refund dialog.

## Impact

- Backend: a new action built on Shopify's order-edit session (begin, change, commit) and the order invoice.
- Dashboard: an edit dialog using the product search of `new-order-with-invoice`; no new seam.
- Shopify scopes: **`write_order_edits` (new, optional)**. Without it the action is absent and the panel says why.
- Depends on `new-order-with-invoice` for the product search.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
