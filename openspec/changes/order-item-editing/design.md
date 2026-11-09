## Context

See proposal.md. Shopify edits an order through a session: `orderEditBegin` returns a calculated order, changes are staged on it (`orderEditSetQuantity`, `orderEditAddVariant`), and `orderEditCommit` applies them, optionally notifying the customer. Nothing changes in the order until commit. The refund dialog already refunds a custom amount.

## Goals / Non-Goals

**Goals:** the preview is the store's own calculation; an abandoned dialog changes nothing; refunds stay in one place (the refund dialog).

**Non-Goals:** shipped lines; price overrides and line discounts; shipping lines; orders in a currency other than the store's when the store refuses them (its reason is shown).

## Decisions

**D1. One edit session per save, not per dialog.** The dialog keeps the agent's changes in the browser. "Summary" sends them to the backend, which begins a session, stages the changes and returns the calculated totals; "Save" repeats the staging in a fresh session and commits. Alternative rejected: holding a session open while the dialog is open. Sessions left behind by closed tabs and two agents editing at once are harder to reason about than two short sessions.

**D2. Removal is "quantity 0 with restock".** `orderEditSetQuantity(quantity: 0, restock: true)`; reductions restock the difference the same way. The inventory scenario of the spec is checked on a product with tracked stock, which the seed creates.

**D3. The money difference comes from the calculated order** (the amount still to pay, or the amount now refundable). When money is due back, the action's answer carries the amount and the panel opens the refund dialog in the custom-amount mode with it prefilled; the agent confirms there. Alternative rejected: refunding inside the edit. Two code paths for refunds, and the refund dialog's rules (restock, notify, role) would be duplicated.

**D4. The invoice for the balance** is `orderInvoiceSend` after commit, only when the agent chose it and the customer has an email.
*Decided by the founder on 2026-11-06:* the customer gets one email with the payment link. When the agent has the store notify the customer, the store's update email already carries the invoice for the balance (task 1.1), so no second invoice is sent and the dialog shows the invoice as included. The summary says whether the order has an email (not the address); an invoice asked for on an order without one refuses the save before anything is committed (`no_email`, as for a new order). The edit stays saved whatever happens to the invoice afterwards: the record and the note say whether it was sent, refused or is unknown, and it is never sent twice.

**D5. What is editable** is decided from the order's lines (unshipped quantity above zero, not cancelled) for showing the button, and by the store at `orderEditBegin` for everything else; its refusal is shown as is.

**D6. Runner, role, scope gate, record** as for the other actions. `write_order_edits` joins the optional scopes with `can.edit_items`. Task 1.1 confirms the scope and the fields on the test store before any code.

**D7. The card shows the order as it is now** (founder, 2026-11-07): each item's `currentQuantity` and the order's `currentTotalPriceSet`, an item taken off not listed; the store's original `quantity` and `totalPriceSet` stay in the panel's answer for whatever else reads them. Before this an edited order kept showing its original items and total, and so did a refunded one. After an action the panel reads as many orders as it showed and replaces them at once, so the card of an order further down, and the refund dialog it opened, stay where they were (found by the end-to-end run of task 4.2).

## Risks / Trade-offs

- [The order changed in the store between summary and save] → the commit runs on a fresh calculation; when its totals differ from the summary shown, nothing is committed and the agent sees the new summary.
- [The store notifies the customer in the merchant's template] → the checkbox says so.
- [An edit plus a refund are two steps] → the panel leads into the second with the amount; the record of the edit names the amount due.

## Findings of task 1.1 (live store, 2026-11-06)

Probed on the development store with API 2026-10: the guide's app (with `write_order_edits`) edited, the seeding app created and removed the data; a second development store, whose app lacks the scope, gave the refusal. Nothing was left in either store.

- **Scope.** Without `write_order_edits` the store refuses `orderEditBegin` with a GraphQL error, code `ACCESS_DENIED`: "Requires `write_order_edits` access scope". `orderInvoiceSend` needs no order-edit scope: an app with `write_orders` reaches it. `Order.merchantEditable` and `merchantEditableErrors` are readable with `read_orders` alone.
- **Which orders the store lets an app edit.** An order created by another app with `orderCreate` is refused at `orderEditBegin` ("The order cannot be edited."), and `merchantEditableErrors` says "This order cannot be edited by this app."; `orderCreate` cannot set a source name like `web` either ("protected value"). An order completed from a draft is editable. A cancelled order is refused the same way, its reason "Canceled orders can't be edited.". So the end-to-end data of this change are orders completed from drafts, not `orderCreate` orders (task 1.3).
- **Ids.** `orderEditBegin` returns a session and a calculated order with the same number; the other mutations take either id. A calculated line has the number of the order's line (`CalculatedLineItem/<n>` for `LineItem/<n>`), so the dialog's line ids map without a lookup. A line added in the session gets a temporary id (a UUID).
- **Editable quantity** is `editableQuantity` of the calculated line: the units not shipped. A shipped line has 0. Setting a shipped line to 0 is answered without a user error and without effect, so the backend checks the editable quantity itself before staging.
- **Nothing before commit.** A session that is not committed leaves the order and the stock as they were; a new `orderEditBegin` starts a fresh session. Abandoned sessions need no cleanup.
- **Money.** `totalOutstandingSet` of the calculated order is the difference after the staged changes: positive is what the customer owes, negative what is due back (a paid order of 1109.95 reduced by one item of 80 shows −80.00). After the commit the order's own `totalOutstandingSet` carries the same number and `currentTotalPriceSet` the new total; `totalPriceSet` keeps the original total plus additions. No money moves on commit: `totalRefundedSet` stays 0, while the store adds a refund record of amount 0 for the removed units. An order that owes after an addition is shown as partly paid.
- **Stock.** `orderEditSetQuantity(restock: true)` on an unshipped unit of a tracked product moves it from committed back to available (8 → 9 for one unit; 9 → 10 when the last one was removed). A removed line stays on the order with `quantity` unchanged and `currentQuantity` 0.
- **Adding.** `orderEditAddVariant` adds a variant at its current price. With `allowDuplicates: false` a variant already on the order is refused ("… was not added because it's already on the order."); the backend therefore raises the quantity of the line that has the variant and units left to ship, and adds a new line otherwise.
- **Notification and invoice.** `orderEditCommit(notifyCustomer: true)` on an edit that leaves the customer owing answers "Order updated", "Invoice sent": the store's update email carries the invoice for the balance by itself. `orderInvoiceSend` after the commit sends the invoice again; with no balance it is refused ("No outstanding balance exist").
- **A fully shipped order** can still be opened for editing and have a product added by the store; the panel does not offer the action for it (D5).
- **The invoice on the order** (D4, checked the same day): the helpdesk's app reads the order's email (`originalOrder.email` of the edit session), so the summary can say whether an invoice can be emailed. After `orderInvoiceSend` the store records an event `invoice_sent` on the order ("… sent invoice #1534 to …"); the end-to-end test checks the invoice by that event.
- **Refund after an edit** (D3, checked the same day): on a paid order of 1771.90, one unit of 885.95 removed by an edit left the order paid with nothing refunded and a balance of −885.95; the refund dialog's path in the amount mode (`refund_suggestion` for the payments, `refund_create` for 885.95) was accepted, the order became partly refunded and its balance 0.00.
