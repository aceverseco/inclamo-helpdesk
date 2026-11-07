## Why

A customer writes "add one more of the same" or "I want to order by chat". Today the agent can only make a free replacement; a paid order needs the store's admin. Four of the five e-commerce helpdesks this project is measured against create an order from the conversation and send the customer an invoice with a payment link. This was planned for release 0.2 and was moved up by the founder's decision of 2026-11-06.

## What Changes

- **"New order"** in the order panel for the matched customer: catalogue search, variants and quantities, an optional discount, a shipping charge, a note; totals are calculated by the store before anything is created.
- The order can **start from an existing order** of the customer ("order again").
- The result is an unpaid order in the store with a **payment link**: the store emails its invoice to the customer, or the agent puts the link into the reply.
- The panel lists the customer's **orders awaiting payment** with their payment links until they are paid.

Not in this change: marking an order as paid without a payment, custom items that are not in the catalogue, taking a payment inside the helpdesk.

## Capabilities

### New Capabilities
- `order-creation`: how an agent builds a paid order for a customer from a conversation, how the customer gets the payment link, what the panel shows until it is paid, who may do it and what record it leaves.

### Modified Capabilities
- none.

## Assumptions (confirmed by the founder on 2026-11-07)

1. The agent cannot mark the new order as paid; money goes only through the store's payment link.
2. Only catalogue products can be added, no free-text items.
3. The discount is one for the whole order: a percentage or an amount.

## Impact

- Backend: a new action on top of the draft-order code the free replacement already uses; a calculation call for the preview; a list of the customer's open drafts.
- Dashboard: a dialog with a product search (shared later with order editing and the reply inserts); a block of orders awaiting payment in the panel; no new seam.
- Shopify scopes: `write_draft_orders` and `read_products`, both already used by the replacement. No new scope.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
