## Why

Chatwoot's automation rules know the channel, the text and the contact, but nothing about the store: a rule cannot say "this customer spent more than 500, give the conversation high priority and the senior team". Every e-commerce helpdesk this project is measured against offers conditions on the customer's spend, order count and tags and on the latest order's status. The release plan also promises preset rules that a merchant switches on with one toggle.

## What Changes

- **Store facts on every new conversation**: for a contact matched to a store customer, the customer's order count, total spent and tags, and the latest order's payment status, fulfilment status, total and tags are available as conditions in Chatwoot's own automation rule editor.
- **Rules see the facts**: the facts are written before the rules of a new conversation are evaluated. The order named in the first message is tied before that too, so a rule's message can use the order variables.
- **Preset rules** on a settings page: each is an ordinary Chatwoot automation rule created by one switch, which the administrator can then edit like any other.

Not in this change: rules started by events in the store (an order was shipped, a refund was made), rule steps that change the store, conditions on products.

## Capabilities

### New Capabilities
- `store-data-rules`: which store facts a rule can use, when they are written, what happens when the store is silent or hides customer data, and how preset rules are switched on and off.

### Modified Capabilities
- `conversation-order-panel`: "order and customer data are not kept" now names a second exception next to the attributes of the marked order: the eight store facts of the customer on the conversation. No name, email, phone or address is among them. Found while building this change; confirmed by the founder on 2026-11-06.

## Assumptions to confirm

1. Confirmed by the founder on 2026-11-06, with two corrections: the three presets are ours: "VIP customers first" (total spent more than an amount the administrator enters, not "at or above": Chatwoot's rules have no such comparison; high priority and the label `vip`), "Order not shipped yet" (latest order unfulfilled: label `awaiting-shipment`), "No orders yet" (the contact is not a customer of the store, or is one who has not ordered yet: label `pre-sale`).
2. Confirmed by the founder on 2026-11-06: facts are written when the conversation is created and refreshed when an agent opens the panel; they are not refreshed on every message.

## Impact

- Backend: an enrichment step in front of Chatwoot's automation listener, new conversation attributes with their definitions, a presets endpoint.
- Dashboard: one more page in our settings registry, and one new seam, carried as a patch: the comparisons the rule editor offers for a custom attribute become extensible, so the store's numbers get "greater than" and "less than" and its texts "contains". Confirmed by the founder on 2026-11-06.
- No new Shopify scope (`read_customers`, `read_orders` are already mandatory). No new table: a preset is recognised by a marker in the rule it created.
- Depends on `reply-order-variables` for the order variables in a rule's message.
- Tests: backend specs, component tests, end-to-end tests for every scenario.
