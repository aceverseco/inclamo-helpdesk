## Context

See proposal.md. The free replacement already creates, updates, completes and deletes a draft order (`replacement_draft_*` documents) and searches variants with `read_products`. The dashboard has an event to put text into the reply editor (`INSERT_INTO_RICH_EDITOR`), used by Chatwoot's own features.

## Goals / Non-Goals

**Goals:** reuse the draft-order code; the store calculates every price; no money handled by us.

**Non-Goals:** completing a draft as paid; custom line items; per-line discounts; choosing among several addresses; reserving stock.

## Decisions

**D1. A draft order that stays a draft.** The action creates a draft order with the chosen lines, discount and shipping line, tagged `inclamo-helpdesk`. It is not completed: completion happens in the store when the customer pays through the invoice link. This is the difference from the replacement, which completes its draft as a free order at once.

**D2. Preview by `draftOrderCalculate`.** The summary shows the store's own numbers (taxes, discount, shipping). Nothing is created until the agent confirms, so an abandoned dialog leaves no draft behind.

**D3. Two deliveries of the link.** "Email the invoice" calls `draftOrderInvoiceSend` with the store's default template. "Insert into the reply" emits Chatwoot's editor-insert event with the draft's `invoiceUrl`. Task 1.2 confirms on the stand that the event reaches the reply box from a sidebar component and what it does in a plain-text channel; if it does not, the link is shown with a copy button and the spec scenario is re-opened with the founder.
*Probed on the stand on 2026-11-06 (task 1.2):* it works. The event goes through Chatwoot's one global emitter, so where it is emitted from does not matter; the reply editor listens (`enable-insert-events`) and the conversation view unfolds the reply box on it. Emitted from outside the reply box with the payment link as text, the link appeared at the cursor in all three inboxes tried: in a web widget inbox and an email inbox as a link (`<a href>`; the message is stored as `<url>`), in an API inbox (plain text) as the plain URL. Nothing is sent: the agent sends the reply. The editor keeps its mode, so when it is set to a private note the link lands in the note. There is no event to switch the mode, so the dialog says where the link goes. The sidebar emits the bare URL, not a Markdown link, so each channel shows it in its own way.

**D4. The list of orders awaiting payment** is `draftOrders` filtered by the customer, the statuses "open" and "invoice sent" (see the findings below) and our tag, five newest. It rides on the panel's existing cache and is dropped after the action.

**D5. The product search is one shared component and endpoint** (title or SKU, variants with price and availability). Order editing and the reply inserts reuse it; it is built here because this change comes first.

**D6. Runner, role, record** as for the other actions; the action row stores the draft's id, total and delivery, no customer data.

## Risks / Trade-offs

- [The store's invoice email is the merchant's template, not ours] → said in the dialog next to the choice.
- [Drafts pile up unpaid] → they are the merchant's ordinary drafts, visible in the admin; the panel lists only five.
- [`read_draft_orders` needed for the list] → task 1.1 confirms the list works with `write_draft_orders` alone; if not, the scope is added as optional and the list hides without it.

## Findings on the test store (task 1.1, 2026-11-06)

Probed with the bench app, which holds exactly the guide's scopes, on Admin API 2026-10; everything it created was removed.

- **Scopes.** The store grants `read_draft_orders` together with `write_draft_orders`: creating, calculating, sending the invoice, reading a draft and listing drafts all work with the guide's scopes. No new scope; the risk above is closed.
- **Calculate.** `draftOrderCalculate` with `purchasingEntity.customerId` and `useCustomerDefaultAddress` returns the lines, subtotal, discounts, shipping, tax and total, and creates nothing (the list stays empty afterwards). A percentage discount (10 % of 2285.85 → 228.58) and an amount (`FIXED_AMOUNT` with `amountWithCurrency`) both work, as does a custom shipping line with `priceWithCurrency`. A bad input comes back as `userErrors` in the store's words ("Quantity must be greater than or equal to 1", "Product with ID 1 is no longer available."): these are the reason the dialog shows.
- **Create is not idempotent.** `draftOrderCreate` accepts `@idempotent(key:)` but a second call with the same key and input made a second draft. So the key is not used. Instead every draft carries a metafield `inclamo.action_id` holding the action id (invisible to the customer), and an attempt whose answer was lost is settled by looking for that marker among the customer's drafts with our tag. The store's search showed a new draft after 1–3 seconds, so a lost attempt is looked for only once its record is 30 seconds old; before that it stays `unknown`. Only the request that started the action creates a draft; a repeated request or a panel read only looks for it, so even a read that comes between saving the record and asking the store cannot make a second draft. Not found after 30 seconds means nothing was created: the attempt is refused as `not_created`.
- **D4 statuses.** After `draftOrderInvoiceSend` the draft's status is `INVOICE_SENT`, not `OPEN`; a paid draft is `COMPLETED` and has an `order`. The list therefore asks for `customer_id:<id> tag:inclamo-helpdesk (status:open OR status:invoice_sent)`.
- **Invoice without an email.** For a customer with a phone and no email the draft is created, but the invoice is refused with "To can't be blank" — the "no email" rule is needed on the server too, not only in the dialog. With an email, `draftOrderInvoiceSend` without an `email` argument sends the store's default invoice to the customer's address and sets `invoiceSentAt`.
- **Product search.** A plain word matches gift cards, archived and draft products too. The search sends `status:active AND gift_card:false AND ((<word>* <word>*) OR sku:"<text>")`: each word as a prefix, or the whole text as a SKU. Quotes, brackets, colons and a leading minus are removed from the agent's text first. A sold-out variant comes back with `availableForSale: false`. The image is `featuredMedia.preview.image.url`.
