# order-creation Specification

## Purpose

Lets an agent build a paid order for the customer of a conversation and hand the customer a payment link, without leaving the helpdesk and without touching money.

## Requirements

### Requirement: An agent builds a new order for the matched customer
An agent holding the order-actions role, and any administrator, SHALL be able to start a new order for the customer matched to the conversation, on a connection that has `write_draft_orders` and `read_products`. The agent SHALL search the store's catalogue by product title or SKU, choose variants and quantities, optionally set one discount for the whole order (a percentage or an amount) and a shipping charge (none or an amount), and optionally add a note. Before the order is created the agent SHALL see the totals as the store calculates them: items, discount, shipping, taxes and the total. The action SHALL NOT be offered in the limited mode, to an agent without the role, or when a needed scope is missing; in the last case the panel SHALL name the missing permission.

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
- **WHEN** an agent without the order-actions role opens the panel
- **THEN** "New order" is not offered to them

#### Scenario: Permission missing
- **WHEN** an administrator opens the panel on a connection without `write_draft_orders`
- **THEN** "New order" is not offered and a line names the missing permission

### Requirement: The customer gets a payment link
On confirmation the order SHALL be created in the store as unpaid, for that customer and their default address. The agent SHALL choose how the customer gets the payment link: the store emails its invoice to the customer's email, or the link is inserted into the reply the agent is writing. Emailing SHALL be offered only when the customer has an email. The helpdesk SHALL NOT mark the order as paid and SHALL NOT take a payment. When the store refuses to create the order, the dialog SHALL show the store's reason and nothing SHALL be created.

#### Scenario: Invoice sent by the store
- **WHEN** the agent confirms the order and chooses "email the invoice"
- **THEN** an unpaid order for that customer exists in the store and the store has sent its invoice to the customer's email

#### Scenario: Link put into the reply
- **WHEN** the agent confirms the order and chooses "insert the link into the reply"
- **THEN** the reply editor contains the payment link of the new order and no invoice email is sent

#### Scenario: Customer without an email
- **WHEN** the matched customer has a phone and no email
- **THEN** only "insert the link into the reply" is offered

#### Scenario: Store refuses
- **WHEN** the store refuses to create the order
- **THEN** the dialog shows the store's reason and no order awaiting payment appears

### Requirement: Orders awaiting payment are visible and recorded
The panel SHALL list the customer's orders awaiting payment that were created from the helpdesk, each with its items, total, payment link and a link to it in the store's admin, until they are paid or deleted in the store; a paid one SHALL appear among the customer's orders. Creating an order SHALL leave a private note in the conversation naming the agent, the total and how the link was delivered.

#### Scenario: Order awaiting payment in the panel
- **WHEN** an agent created an order and the customer has not paid it
- **THEN** the panel shows it as awaiting payment with its total and payment link

#### Scenario: Record of the new order
- **WHEN** an agent creates an order and emails the invoice
- **THEN** the conversation gets a private note saying who created an order, for which total, and that the invoice was emailed
