## Why

"Which one fits my car?" is answered with a product link, and "sorry for the delay" often with a discount code. Today the agent finds the product in the storefront and creates the code in the store's admin, then pastes both. Two of the five e-commerce helpdesks this project is measured against insert a product into the reply, and one creates a discount code from the conversation.

## What Changes

- **"Insert product"**: catalogue search by title or SKU; the chosen product's title, price and storefront link go into the reply the agent is writing. Any agent can do it.
- **"Discount code"**: an agent with the order-actions role creates a single-use code (a percentage or an amount, with an expiry), for this customer only when the customer is known; the code goes into the reply.
- The code needs one more permission of the merchant's app, `write_discounts`.
- Creating a code leaves a private note in the conversation.

Not in this change: product cards with pictures in the chat widget, cart or checkout links, free-shipping and buy-X-get-Y codes, a ceiling on what an agent may give.

## Capabilities

### New Capabilities
- `reply-inserts`: how a product and a new discount code get into the reply, what the code is limited to, who may create it and what record it leaves.

### Modified Capabilities
- none.

## Assumptions to confirm

1. There is no ceiling on the discount an agent may give; the order-actions role is the only gate, as for refunds.
2. A code works once. It is tied to the customer when the conversation's customer is known, and open to anyone otherwise.
3. The expiry choices are 7 days, 30 days (the default) and none.

## Impact

- Backend: a discount action in the existing runner; the product search of `new-order-with-invoice` is reused.
- Dashboard: two controls in the Orders section and their dialogs; text goes into the reply through Chatwoot's own editor-insert event; no new seam.
- Shopify scopes: `read_products` (already used) for the product; **`write_discounts` (new, optional)** for the code.
- Depends on `new-order-with-invoice` for the product search and for the check of the editor-insert event.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
