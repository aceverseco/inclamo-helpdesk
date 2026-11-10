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

**D5. What is editable** is decided from the order's lines (unshipped quantity above zero, not cancelled) for showing the button, and by the store at `orderEditBegin` for everything else; its refusal is shown as is.

**D6. Runner, role, scope gate, record** as for the other actions. `write_order_edits` joins the optional scopes with `can.edit_items`. Task 1.1 confirms the scope and the fields on the test store before any code.

## Risks / Trade-offs

- [The order changed in the store between summary and save] → the commit runs on a fresh calculation; when its totals differ from the summary shown, nothing is committed and the agent sees the new summary.
- [The store notifies the customer in the merchant's template] → the checkbox says so.
- [An edit plus a refund are two steps] → the panel leads into the second with the amount; the record of the edit names the amount due.
