## Context

See proposal.md. The free replacement already creates, updates, completes and deletes a draft order (`replacement_draft_*` documents) and searches variants with `read_products`. The dashboard has an event to put text into the reply editor (`INSERT_INTO_RICH_EDITOR`), used by Chatwoot's own features.

## Goals / Non-Goals

**Goals:** reuse the draft-order code; the store calculates every price; no money handled by us.

**Non-Goals:** completing a draft as paid; custom line items; per-line discounts; choosing among several addresses; reserving stock.

## Decisions

**D1. A draft order that stays a draft.** The action creates a draft order with the chosen lines, discount and shipping line, tagged `inclamo-helpdesk`. It is not completed: completion happens in the store when the customer pays through the invoice link. This is the difference from the replacement, which completes its draft as a free order at once.

**D2. Preview by `draftOrderCalculate`.** The summary shows the store's own numbers (taxes, discount, shipping). Nothing is created until the agent confirms, so an abandoned dialog leaves no draft behind.

**D3. Two deliveries of the link.** "Email the invoice" calls `draftOrderInvoiceSend` with the store's default template. "Insert into the reply" emits Chatwoot's editor-insert event with the draft's `invoiceUrl`. Task 1.2 confirms on the stand that the event reaches the reply box from a sidebar component and what it does in a plain-text channel; if it does not, the link is shown with a copy button and the spec scenario is re-opened with the founder.

**D4. The list of orders awaiting payment** is `draftOrders` filtered by the customer, the status "open" and our tag, five newest. It rides on the panel's existing cache and is dropped after the action.

**D5. The product search is one shared component and endpoint** (title or SKU, variants with price and availability). Order editing and the reply inserts reuse it; it is built here because this change comes first.

**D6. Runner, role, record** as for the other actions; the action row stores the draft's id, total and delivery, no customer data.

## Risks / Trade-offs

- [The store's invoice email is the merchant's template, not ours] → said in the dialog next to the choice.
- [Drafts pile up unpaid] → they are the merchant's ordinary drafts, visible in the admin; the panel lists only five.
- [`read_draft_orders` needed for the list] → task 1.1 confirms the list works with `write_draft_orders` alone; if not, the scope is added as optional and the list hides without it.
