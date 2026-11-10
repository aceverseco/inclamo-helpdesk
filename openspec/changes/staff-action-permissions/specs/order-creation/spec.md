## MODIFIED Requirements

### Requirement: An agent builds a new order for the matched customer
An agent holding the new-order permission, and any administrator, SHALL be able to start a new order for the customer matched to the conversation, on a connection that has `write_draft_orders` and `read_products`. The agent SHALL search the store's catalogue by product title or SKU, choose variants and quantities, optionally set one discount for the whole order (a percentage or an amount) and a shipping charge (none or an amount), and optionally add a note. Adding a discount SHALL also require the separate discount permission. Before the order is created the agent SHALL see the totals as the store calculates them: items, discount, shipping, taxes and the total. The action SHALL NOT be offered in the limited mode, to an agent without the new-order permission, or when a needed scope is missing; in the last case the panel SHALL name the missing permission.

#### Scenario: Order with two products
- **WHEN** an agent with the role searches the catalogue, adds two products with quantities 1 and 2, and opens the summary
- **THEN** the summary shows both lines and the total calculated by the store

#### Scenario: Discount and shipping charge
- **WHEN** the agent sets a 10 % discount and a shipping charge of 5.00 on that order
- **THEN** the summary shows the discount, the shipping charge and the new total

#### Scenario: Starting from an existing order
- **WHEN** the agent chooses "order again" on an existing order of the customer
- **THEN** the new order starts with that order's items and quantities, and the agent can change them before the summary

#### Scenario: Agent without the role
- **WHEN** an agent without the new-order permission opens the panel
- **THEN** "New order" is not offered to them

#### Scenario: Permission missing
- **WHEN** an administrator opens the panel on a connection without `write_draft_orders`
- **THEN** "New order" is not offered and a line names the missing permission

#### Scenario: New-order permission does not grant discounts
- **WHEN** staff with new-order permission but no discount permission submit a discounted new order
- **THEN** the server refuses it without creating a draft order
