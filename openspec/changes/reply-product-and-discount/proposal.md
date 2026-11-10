## Why

"Which one fits my car?" is answered with a product link, and "sorry for the delay" often with a discount code. Today the agent finds the product in the storefront and creates the code in the store's admin, then pastes both. Two of the five e-commerce helpdesks this project is measured against insert a product into the reply, and one creates a discount code from the conversation.

## What Changes

- **"Insert product"**: catalogue search by title or SKU; the chosen product's title, price and storefront link go into the reply the agent is writing. Any agent can do it.
- **Discount presets**: an administrator sets up, once, the discounts agents may give. Each preset has a name, a value (a percentage or an amount), an expiry in days or none, a number of uses and an audience (this customer only, or anyone).
- **The right to give discounts**: an administrator gives it per agent. It is separate from the order-actions role; administrators always hold it.
- **"Discount code"**: an agent with the right picks a preset and nothing else; the store creates the code with the preset's conditions and a text the helpdesk makes, and the code goes into the reply. A preset for this customer only is not offered when the conversation's contact is not a customer of the store.
- The code needs one more permission of the merchant's app, `write_discounts`.
- Creating a code leaves a private note in the conversation.

Not in this change: product cards with pictures in the chat widget, cart or checkout links, free-shipping and buy-X-get-Y codes, presets limited to some products, editing or deleting codes later.

## Capabilities

### New Capabilities
- `reply-inserts`: how a product and a new discount code get into the reply, the presets an administrator sets, the right to give discounts, and what record a code leaves.

### Modified Capabilities
- none.

## Decisions of the founder (2026-11-06)

1. The size of a discount and its other conditions are set once in the settings as several presets; the agent only picks one.
2. A preset holds a name, a value (percentage or amount), an expiry in days, a number of uses and an audience (this customer only / anyone). An empty expiry means the code never expires.
3. The right to give discounts is assigned by an administrator and is separate from the order-actions role.
4. A preset for this customer only is not offered when the contact matches no customer.
5. The code's text is made by the helpdesk; the agent cannot change it.

## Assumptions to confirm

1. A code for anyone with several uses works once per buyer; a code for this customer with several uses works that many times for that customer.
2. The presets and the right to give discounts share one settings page, "Discount codes".
3. A refused code is kept in the action record like every other refused action (as the order actions already do), but leaves no note in the conversation.

## Impact

- Backend: two tables (presets, the right), their administrator endpoints, a discount action on the runner's order-less path of `new-order-with-invoice`; the product search of `new-order-with-invoice` is reused and extended with the storefront link.
- Dashboard: one settings page in our settings registry; two controls in the Orders section and their dialogs; text goes into the reply through `insertIntoReply` of `new-order-with-invoice`; no new seam.
- Shopify scopes: `read_products` (already used) for the product; **`write_discounts` (new, optional)** for the code.
- Depends on `new-order-with-invoice` (commit 23a471a): product search, order-less action path, reply insert.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
