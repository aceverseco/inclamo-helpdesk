## Why

A saved reply cannot say "your order #1042 is on its way, here is the tracking link" by itself. The order panel already writes six facts of the conversation's order as conversation attributes, but an agent reaches them only under long technical names (`conversation.custom_attribute.shopify_order_number`), the values are as old as the last time someone opened the panel, and the items, the total and the order status page are not available at all. Every e-commerce helpdesk this project is measured against has order variables in saved replies; it is the first thing an agent looks for after the order panel.

## What Changes

- **Order variables with readable names** (`order.number`, `order.tracking_link`, `order.items` and others) in the variable list of the reply editor, in saved replies and in the message step of a macro.
- **Values are read from the store when the message is sent**, not taken from the last time the panel was open.
- The variables speak about **the order tied to the conversation**. When no order is tied, the agent is warned before sending; a message sent by a macro renders the variables as empty text, never as raw placeholders.
- One new seam in Chatwoot's dashboard: the list of reply variables becomes extensible, carried as a patch.

Not in this change: variables in automation rules (they come with `store-data-rules`, which makes the store data arrive before the rules run), the shipping address as a variable, translated status words.

## Capabilities

### New Capabilities
- `reply-order-variables`: which order variables exist, where they are offered, which order they speak about, how fresh the values are, and what happens when there is no order or the store cannot be reached.

### Modified Capabilities
- none.

## Assumptions to confirm

1. The variables speak about the tied order only. The other helpdesks use "the customer's last order"; here the agent ties the order with one click (or it is tied by the order number in the first message), so a reply never names an order the agent did not look at.
2. Status words are English, the same the panel shows.

## Impact

- Backend: an `order` object for Chatwoot's message templating, fed by the existing order reader and its 60-second cache.
- Dashboard: a third seam (reply variables registry), our entries in it.
- No new Shopify scope. No new table.
- Tests: backend specs on recorded answers, component tests, end-to-end tests for every scenario.
