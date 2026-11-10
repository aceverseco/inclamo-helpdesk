## Purpose

Lets an agent change the items of an order that has not fully shipped, see the money difference before saving, and settle it, without cancelling the order and without the store's admin.

## ADDED Requirements

### Requirement: Unshipped items of an order can be edited
An agent holding the order-actions role, and any administrator, SHALL be able to edit an order that has at least one unshipped item and is not cancelled, on a connection that has `write_order_edits`: change the quantity of an unshipped item, remove it, and add a product from the catalogue. Shipped items SHALL be shown and SHALL NOT be changeable. The action SHALL NOT be offered for a fully shipped or cancelled order, to an agent without the role, or without the scope; in the last case the panel SHALL name the missing permission. Closing the dialog without saving SHALL leave the order unchanged. The order's card SHALL show each item's current quantity and the order's current total, without the items taken off, so that a saved edit shows at once.

#### Scenario: Quantity reduced
- **WHEN** an agent with the role changes an unshipped item from 2 to 1 and saves
- **THEN** the order has quantity 1 of that item in the store

#### Scenario: Item removed
- **WHEN** an agent with the role removes one of two unshipped items and saves
- **THEN** the order no longer contains that item in the store and keeps the other

#### Scenario: Product added
- **WHEN** an agent with the role adds a product from the catalogue and saves
- **THEN** the order contains the new item in the store

#### Scenario: Partly shipped order
- **WHEN** an agent opens "Edit items" on an order with one shipped and one unshipped item
- **THEN** the shipped item is shown without controls and the unshipped one can be changed

#### Scenario: Fully shipped order
- **WHEN** an agent opens a fully shipped order
- **THEN** "Edit items" is not offered

#### Scenario: Closed without saving
- **WHEN** an agent changes a quantity in the dialog and closes it without saving
- **THEN** the order in the store is unchanged

#### Scenario: Permission missing
- **WHEN** an administrator opens an unshipped order on a connection without `write_order_edits`
- **THEN** "Edit items" is not offered and a line names the missing permission

#### Scenario: Agent without the role
- **WHEN** an agent without the order-actions role opens an unshipped order
- **THEN** "Edit items" is not offered to them

#### Scenario: Card after an edit
- **WHEN** an agent reduces an item from 2 to 1 and saves
- **THEN** the order's card shows quantity 1 of that item and the order's new total

### Requirement: The money difference is shown and settled
Before saving the agent SHALL see the order's new total and the difference as the store calculates it: an amount the customer owes, an amount due back to the customer, or no difference. The agent SHALL be able to have the store notify the customer of the change. When the customer owes an amount, the agent SHALL be able to have the store email an invoice for it. When an amount is due back, saving SHALL NOT refund it; the panel SHALL say how much is due and SHALL offer the refund dialog with that amount. An unshipped item taken off the order SHALL go back to stock.

#### Scenario: Customer owes more
- **WHEN** an agent adds a product to a paid order, chooses to email the invoice and saves
- **THEN** the summary showed the amount owed before saving, and the store has sent the customer an invoice for that amount

#### Scenario: Money due back
- **WHEN** an agent removes an item from a paid order and saves
- **THEN** the summary showed the amount due back, no refund is made by saving, and the panel offers the refund dialog with that amount

#### Scenario: Removed item back in stock
- **WHEN** an agent removes an unshipped item of a product whose stock is tracked and saves
- **THEN** the product's available quantity in the store is higher by the removed quantity

### Requirement: Every edit leaves a record and failures are shown
A saved edit SHALL leave a private note in the conversation naming the agent, the order, each change (added, removed, quantity from and to) and the money difference. When the store refuses the edit, the dialog SHALL show the store's reason and the order SHALL stay unchanged.

#### Scenario: Record of an edit
- **WHEN** an agent reduces an item from 2 to 1 on order #1042 and saves
- **THEN** the conversation gets a private note saying who changed which item from 2 to 1 on #1042 and the amount due back

#### Scenario: Store refuses the edit
- **WHEN** the store refuses the edit
- **THEN** the dialog shows the store's reason and the order's items are as before
